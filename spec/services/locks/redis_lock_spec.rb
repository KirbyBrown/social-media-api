# frozen_string_literal: true

require "rails_helper"

RSpec.describe Locks::RedisLock do
  let(:fake_redis_class) do
    Class.new do
      attr_reader :store, :sets

      def initialize
        @store = {}
        @sets = 0
      end

      def set(key, value, nx: false, ex: nil)
        @sets += 1
        return false if nx && @store.key?(key)

        @store[key] = value
        true
      end

      def eval(_lua, keys:, argv:)
        @store.delete(keys.first) if @store[keys.first] == argv.first
      end

      def close; end
    end
  end

  before do
    allow_any_instance_of(described_class).to receive(:around).and_call_original
  end

  it "yields under a held lock and releases it" do
    redis = fake_redis_class.new
    ran = false

    described_class.new("post-1", redis:, attempts: 1, wait: 0).around { ran = true }

    expect(ran).to be(true)
    expect(redis.store).to be_empty
  end

  it "still yields when the lock is busy" do
    redis = fake_redis_class.new
    redis.store["lock:post-1"] = "other"

    described_class.new("post-1", redis:, attempts: 1, wait: 0).around { nil }

    expect(redis.sets).to eq(1)
    expect(redis.store["lock:post-1"]).to eq("other")
  end

  it "still yields when Redis is down" do
    redis = double(close: true)
    allow(redis).to receive(:set).and_raise(Redis::CannotConnectError, "Connection refused redis://10.0.0.8:6379")
    ran = false

    described_class.new("post-1", redis:, attempts: 1, wait: 0).around { ran = true }

    expect(ran).to be(true)
  end
end
