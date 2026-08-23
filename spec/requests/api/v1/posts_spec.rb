# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Posts" do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{bearer_token(user)}" }

  path "/api/v1/posts" do
    get "Lists kept posts" do
      tags "Posts"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string
      parameter name: :page, in: :query, type: :integer, required: false

      response "200", "paginated list" do
        before { create_list(:post, 2, user:) }

        let(:page) { 1 }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["posts"].size).to eq(2)
          expect(body["pagination"]).to include("page" => 1, "count" => 2)
        end
      end

      response "200", "omits soft-deleted posts" do
        before do
          create(:post, user:, title: "Visible")
          create(:post, :deleted, user:, title: "Gone")
        end

        let(:page) { 1 }

        run_test! do |response|
          titles = JSON.parse(response.body)["posts"].map { |p| p["title"] }
          expect(titles).to eq([ "Visible" ])
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

    post "Creates a post" do
      tags "Posts"
      consumes "application/json"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string
      parameter name: :params, in: :body, schema: {
        type: :object,
        properties: {
          post: {
            type: :object,
            properties: {
              title: { type: :string },
              body: { type: :string }
            },
            required: %w[title body]
          }
        },
        required: %w[post]
      }

      response "201", "created" do
        let(:params) { { post: { title: "Hello", body: "World" } } }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.dig("post", "title")).to eq("Hello")
          expect(body.dig("post", "user", "id")).to eq(user.id)
        end
      end

      response "422", "title too long" do
        let(:params) { { post: { title: "x" * 101, body: "World" } } }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "details")).to include("title")
        end
      end
    end
  end

  path "/api/v1/posts/{id}" do
    parameter name: :id, in: :path, type: :string
    parameter name: :Authorization, in: :header, type: :string

    get "Shows a kept post" do
      tags "Posts"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      response "200", "found" do
        let(:record) { create(:post, user:, views_count: 0) }
        let(:id) { record.id }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.dig("post", "id")).to eq(record.id)
          expect(body.dig("post", "views_count")).to eq(1)
        end
      end

      response "404", "soft-deleted" do
        let(:record) { create(:post, :deleted, user:) }
        let(:id) { record.id }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "code")).to eq("not_found")
        end
      end
    end

    patch "Updates own post" do
      tags "Posts"
      consumes "application/json"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :params, in: :body, schema: {
        type: :object,
        properties: {
          post: {
            type: :object,
            properties: {
              title: { type: :string },
              body: { type: :string }
            }
          }
        }
      }

      response "200", "updated" do
        let(:record) { create(:post, user:, title: "Old") }
        let(:id) { record.id }
        let(:params) { { post: { title: "New" } } }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("post", "title")).to eq("New")
        end
      end

      response "404", "another user's post" do
        let(:record) { create(:post, title: "Not yours") }
        let(:id) { record.id }
        let(:params) { { post: { title: "Hijack" } } }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "code")).to eq("not_found")
        end
      end
    end

    delete "Soft-deletes own post" do
      tags "Posts"
      security [ { bearerAuth: [] } ]

      response "204", "deleted" do
        let(:record) { create(:post, user:) }
        let(:id) { record.id }

        run_test! do
          expect(record.reload.deleted_at).to be_present
          expect(Post.exists?(record.id)).to be(true)
        end
      end
    end
  end
end
