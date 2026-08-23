# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Sessions" do
  path "/api/v1/sessions" do
    post "Creates a session" do
      tags "Sessions"
      consumes "application/json"
      produces "application/json"
      parameter name: :params, in: :body, schema: {
        type: :object,
        properties: {
          email: { type: :string, example: "kirby@example.com" },
          username: { type: :string, example: "kirby" },
          password: { type: :string, example: "password123" }
        }
      }

      response "200", "authenticated with email" do
        let!(:user) { create(:user, email: "kirby@example.com", password: "password123") }
        let(:params) { { email: "kirby@example.com", password: "password123" } }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["token"]).to be_present
          expect(body.dig("user", "email")).to eq("kirby@example.com")
        end
      end

      response "200", "authenticated with username" do
        let!(:user) { create(:user, username: "kirby", password: "password123") }
        let(:params) { { username: "kirby", password: "password123" } }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.dig("user", "username")).to eq("kirby")
        end
      end

      response "401", "invalid credentials" do
        let!(:user) { create(:user, email: "kirby@example.com", password: "password123") }
        let(:params) { { email: "kirby@example.com", password: "wrong-password" } }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.dig("error", "code")).to eq("unauthorized")
          expect(body.dig("error", "message")).to eq("Invalid credentials")
        end
      end
    end
  end
end
