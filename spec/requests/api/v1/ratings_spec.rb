# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Ratings" do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{bearer_token(user)}" }
  let(:post_record) { create(:post) }
  let(:post_id) { post_record.id }

  path "/api/v1/posts/{post_id}/rating" do
    parameter name: :post_id, in: :path, type: :string
    parameter name: :Authorization, in: :header, type: :string

    put "Creates or updates the current user's rating" do
      tags "Ratings"
      consumes "application/json"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :params, in: :body, schema: {
        type: :object,
        properties: {
          rating: {
            type: :object,
            properties: {
              value: { type: :integer, minimum: 1, maximum: 5 }
            },
            required: %w[value]
          }
        },
        required: %w[rating]
      }

      response "200", "created" do
        let(:params) { { rating: { value: 5 } } }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.dig("rating", "value")).to eq(5)
          expect(body.dig("rating", "user_id")).to eq(user.id)
          expect(body.dig("post", "ratings_count")).to eq(1)
          expect(body.dig("post", "average_rating").to_d).to eq(5)
        end
      end

      response "200", "updated" do
        before { Ratings::Upsert.new(user:, post: post_record, value: 2).call }

        let(:params) { { rating: { value: 4 } } }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.dig("rating", "value")).to eq(4)
          expect(user.ratings.where(post: post_record).count).to eq(1)
          expect(body.dig("post", "ratings_count")).to eq(1)
          expect(body.dig("post", "average_rating").to_d).to eq(4)
        end
      end

      response "422", "value out of range" do
        let(:params) { { rating: { value: 6 } } }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "details")).to include("value")
        end
      end

      response "400", "missing rating key" do
        let(:params) { { value: 5 } }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "code")).to eq("bad_request")
        end
      end

      response "404", "soft-deleted post" do
        let(:post_record) { create(:post, :deleted) }
        let(:params) { { rating: { value: 5 } } }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "code")).to eq("not_found")
        end
      end

      response "401", "unauthenticated" do
        let(:Authorization) { nil }
        let(:params) { { rating: { value: 5 } } }

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "code")).to eq("unauthorized")
        end
      end
    end
  end
end
