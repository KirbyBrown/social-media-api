# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Timeline" do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{bearer_token(user)}" }

  path "/api/v1/timeline" do
    get "Lists the newest kept posts" do
      tags "Timeline"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :min_rating, in: :query, type: :number, required: false

      response "200", "newest first" do
        before do
          create(:post, title: "Older", created_at: 2.days.ago)
          create(:post, title: "Newer", created_at: 1.hour.ago, average_rating: 5, ratings_count: 1)
        end

        let(:page) { 1 }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["posts"].map { |post| post["title"] }).to eq(%w[Newer Older])
          expect(body["posts"].first).to include("user", "average_rating", "ratings_count")
          expect(body["pagination"]).to include("page" => 1, "count" => 2)
        end
      end

      response "200", "min_rating filter" do
        before do
          create(:post, title: "Low", average_rating: 2)
          create(:post, title: "High", average_rating: 4)
        end

        let(:page) { 1 }
        let(:min_rating) { 4 }

        run_test! do |response|
          titles = JSON.parse(response.body)["posts"].map { |post| post["title"] }
          expect(titles).to eq([ "High" ])
        end
      end

      response "200", "omits soft-deleted posts" do
        before do
          create(:post, title: "Visible")
          create(:post, :deleted, title: "Gone")
        end

        let(:page) { 1 }

        run_test! do |response|
          titles = JSON.parse(response.body)["posts"].map { |post| post["title"] }
          expect(titles).to eq([ "Visible" ])
        end
      end

      response "400", "min_rating out of range" do
        let(:page) { 1 }
        let(:min_rating) { 6 }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "code")).to eq("bad_request")
        end
      end

      response "401", "unauthenticated" do
        let(:Authorization) { nil }
        let(:page) { 1 }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "code")).to eq("unauthorized")
        end
      end
    end
  end

  describe "cache invalidation" do
    it "includes a newly created post after the write" do
      create(:post, title: "Cached")
      get "/api/v1/timeline", headers: auth_headers(user)

      post "/api/v1/posts",
           params: { post: { title: "Fresh", body: "Just posted" } },
           headers: auth_headers(user),
           as: :json

      get "/api/v1/timeline", headers: auth_headers(user)
      titles = JSON.parse(response.body)["posts"].map { |post| post["title"] }
      expect(titles).to include("Fresh", "Cached")
    end

    it "refreshes averages after a rating write" do
      record = create(:post, title: "Rated")
      get "/api/v1/timeline", headers: auth_headers(user)

      put "/api/v1/posts/#{record.id}/rating",
          params: { rating: { value: 5 } },
          headers: auth_headers(user),
          as: :json

      get "/api/v1/timeline", headers: auth_headers(user)
      post_json = JSON.parse(response.body)["posts"].find { |post| post["title"] == "Rated" }
      expect(post_json["ratings_count"]).to eq(1)
      expect(post_json["average_rating"].to_d).to eq(5)
    end
  end
end
