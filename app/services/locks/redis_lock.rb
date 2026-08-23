# frozen_string_literal: true

module Locks
  class RedisLock
    RELEASE = <<~LUA.freeze
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    LUA

    def initialize(name, redis: nil, ttl: 2, attempts: 4, wait: 0.05)
      @name = "lock:#{name}"
      @redis = redis
      @ttl = ttl
      @attempts = attempts
      @wait = wait
    end

    # Contention relief only. The rating row lock is the correctness layer. See SOLUTION.md.
    def around
      client = nil
      owned = false
      token = SecureRandom.uuid

      begin
        client = @redis || Redis.new(url: redis_url, connect_timeout: 0.2, read_timeout: 0.2)
        owned = acquire(client, token)
      rescue Redis::BaseError, RedisClient::Error => e
        Rails.logger.warn("redis lock #{e.class}: #{e.message}")
      end

      yield
    ensure
      release(client, token) if owned && client
      client&.close unless @redis
    end

    private

    def acquire(client, token)
      @attempts.times do |index|
        return true if client.set(@name, token, nx: true, ex: @ttl)

        sleep @wait if index + 1 < @attempts && @wait.positive?
      end
      false
    end

    def release(client, token)
      client.eval(RELEASE, keys: [ @name ], argv: [ token ])
    rescue Redis::BaseError, RedisClient::Error => e
      Rails.logger.warn("redis lock #{e.class}: #{e.message}")
    end

    def redis_url
      ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
    end
  end
end
