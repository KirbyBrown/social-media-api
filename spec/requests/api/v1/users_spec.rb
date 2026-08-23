# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Users" do
  path "/api/v1/users" do
    post "Registers a user" do
      tags "Users"
      consumes "application/json"
      produces "application/json"
      parameter name: :params, in: :body, schema: {
        type: :object,
        properties: {
          user: {
            type: :object,
            properties: {
              username: { type: :string, example: "kirby" },
              email: { type: :string, example: "kirby@example.com" },
              password: { type: :string, example: "password123" }
            },
            required: %w[username email password]
          }
        },
        required: %w[user]
      }

      response "201", "created" do
        let(:params) do
          { user: { username: "kirby", email: "kirby@example.com", password: "password123" } }
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["token"]).to be_present
          expect(body["user"]).to include("username" => "kirby", "email" => "kirby@example.com")
          expect(body["user"]).not_to have_key("password_digest")
        end
      end

      response "422", "validation failed" do
        let(:params) do
          { user: { username: "kirby", email: "not-an-email", password: "short" } }
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.dig("error", "code")).to eq("validation_failed")
          expect(body.dig("error", "details")).to include("email", "password")
        end
      end

      response "422", "duplicate username or email" do
        let!(:existing) { create(:user, username: "kirby", email: "kirby@example.com") }
        let(:params) do
          { user: { username: "kirby", email: "kirby@example.com", password: "password123" } }
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.dig("error", "code")).to eq("validation_failed")
          expect(body.dig("error", "details").keys).to include("username", "email")
        end
      end
    end
  end
end
