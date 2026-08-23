# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Health" do
  def stub_dependencies_up
    allow_any_instance_of(Redis).to receive(:ping).and_return("PONG")
    allow_any_instance_of(Redis).to receive(:close)
    allow(Sidekiq).to receive(:redis).and_yield(double(ping: "PONG"))
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(double(size: 0))
  end

  path "/api/v1/health" do
    get "Reports Postgres, Redis, and Sidekiq" do
      tags "Health"
      produces "application/json"

      response "200", "postgres is up" do
        before { stub_dependencies_up }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["status"]).to eq("ok")
          expect(body.dig("checks", "postgres", "ok")).to be(true)
          expect(body["checks"]).to include("redis", "sidekiq")
        end
      end

      response "200", "redis down is still 200" do
        before do
          allow_any_instance_of(Redis).to receive(:ping).and_raise(Redis::CannotConnectError, "Connection refused")
          allow_any_instance_of(Redis).to receive(:close)
          allow(Sidekiq).to receive(:redis).and_raise(Redis::CannotConnectError, "Connection refused")
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["status"]).to eq("ok")
          expect(body.dig("checks", "redis", "ok")).to be(false)
          expect(body.dig("checks", "redis", "error")).to eq("Redis::CannotConnectError")
        end
      end

      response "503", "postgres is down" do
        before do
          stub_dependencies_up
          allow(ActiveRecord::Base).to receive(:with_connection).and_raise(
            ActiveRecord::ConnectionNotEstablished, "connection is closed on host 10.0.0.8 port 5432"
          )
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["status"]).to eq("unavailable")
          expect(body.dig("checks", "postgres")).to eq(
            "ok" => false,
            "error" => "ActiveRecord::ConnectionNotEstablished"
          )
        end
      end
    end
  end

  it "does not require authentication" do
    stub_dependencies_up

    get "/api/v1/health"

    expect(response).to have_http_status(:ok)
  end
end
