# frozen_string_literal: true

require "rails_helper"

RSpec.describe Health::Check do
  def stub_redis_up
    allow_any_instance_of(Redis).to receive(:ping).and_return("PONG")
    allow_any_instance_of(Redis).to receive(:close)
    allow(Sidekiq).to receive(:redis).and_yield(double(ping: "PONG"))
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(double(size: 0))
  end

  it "is ok when Postgres answers" do
    stub_redis_up
    result = described_class.new.call

    expect(result.ok).to be(true)
    expect(result.http_status).to eq(:ok)
    expect(result.as_json).to include("status" => "ok")
    expect(result.as_json.dig("checks", "postgres")).to eq("ok" => true)
  end

  it "is unavailable when Postgres is down" do
    stub_redis_up
    allow(ActiveRecord::Base).to receive(:with_connection).and_raise(
      ActiveRecord::ConnectionNotEstablished, "connection is closed on host 10.0.0.8 port 5432"
    )

    result = described_class.new.call

    expect(result.ok).to be(false)
    expect(result.http_status).to eq(:service_unavailable)
    expect(result.as_json).to include("status" => "unavailable")
    expect(result.as_json.dig("checks", "postgres")).to eq(
      "ok" => false,
      "error" => "ActiveRecord::ConnectionNotEstablished"
    )
  end

  it "stays ok when Redis is down and reports the exception class" do
    allow_any_instance_of(Redis).to receive(:ping).and_raise(Redis::CannotConnectError, "Connection refused redis://10.0.0.8:6379")
    allow_any_instance_of(Redis).to receive(:close)
    allow(Sidekiq).to receive(:redis)

    result = described_class.new.call

    expect(result.ok).to be(true)
    expect(result.http_status).to eq(:ok)
    expect(result.as_json.dig("checks", "redis")).to eq("ok" => false, "error" => "Redis::CannotConnectError")
    expect(result.as_json.dig("checks", "sidekiq")).to eq("ok" => false, "error" => "Redis::CannotConnectError")
    expect(Sidekiq).not_to have_received(:redis)
  end

  it "caches the probe so a second call does not hit dependencies" do
    stub_redis_up
    described_class.new.call
    described_class.new.call

    expect(Sidekiq::ProcessSet).to have_received(:new).once
  end

  it "lets unexpected errors propagate" do
    stub_redis_up
    allow(ActiveRecord::Base).to receive(:with_connection).and_raise(RuntimeError, "bug")

    expect { described_class.new.call }.to raise_error(RuntimeError, "bug")
  end
end
