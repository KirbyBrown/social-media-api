# frozen_string_literal: true

require "rails_helper"

RSpec.describe "consistent error format" do
  describe "POST /api/v1/users" do
    it "returns 400 in the standard shape when the user key is missing" do
      post "/api/v1/users", params: { username: "kirby" }, as: :json

      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq("bad_request")
      expect(body.dig("error", "details")).to include("user")
    end

    it "returns 422 when a unique index rejects a concurrent user insert" do
      allow_any_instance_of(User).to receive(:save).and_raise(
        ActiveRecord::RecordNotUnique.new("PG::UniqueViolation: index_users_on_username")
      )

      post "/api/v1/users",
           params: { user: { username: "kirby", email: "kirby@example.com", password: "password123" } },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq("validation_failed")
      expect(body.dig("error", "details", "username")).to eq([ "has already been taken" ])
    end
  end

  describe "PUT /api/v1/posts/:post_id/rating" do
    it "returns 503 in the standard shape when a Redis error escapes the write path" do
      user = create(:user)
      record = create(:post)
      allow_any_instance_of(Locks::RedisLock).to receive(:around)
        .and_raise(RedisClient::CannotConnectError, "Connection refused")

      put "/api/v1/posts/#{record.id}/rating",
          params: { rating: { value: 4 } },
          headers: auth_headers(user),
          as: :json

      expect(response).to have_http_status(:service_unavailable)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq("unavailable")
    end
  end
end
