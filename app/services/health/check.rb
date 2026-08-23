# frozen_string_literal: true

require "sidekiq/api"

module Health
  class Check
    CACHE_KEY = "health/check"
    TTL = 3.seconds

    Result = Data.define(:ok, :checks) do
      def http_status
        ok ? :ok : :service_unavailable
      end

      def as_json(*)
        {
          "status" => (ok ? "ok" : "unavailable"),
          "checks" => checks
        }
      end
    end

    def call
      # Cache a few seconds so an unauthenticated probe cannot amplify three dependency trips. See SOLUTION.md.
      payload = Rails.cache.fetch(CACHE_KEY, expires_in: TTL) { probe }
      Result.new(ok: payload.fetch("ok"), checks: payload.fetch("checks"))
    end

    private

    def probe
      redis_check = redis
      checks = {
        "postgres" => postgres,
        "redis" => redis_check,
        "sidekiq" => (redis_check["ok"] ? sidekiq : redis_check)
      }

      { "ok" => checks["postgres"]["ok"], "checks" => checks }
    end

    # Rescue connection errors only. Other exceptions propagate. See SOLUTION.md.
    def postgres
      # with_connection releases the checkout immediately. See SOLUTION.md.
      ActiveRecord::Base.with_connection { |connection| connection.select_value("SELECT 1") }
      { "ok" => true }
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid, PG::Error => e
      failed(e)
    end

    def redis
      client = Redis.new(url: redis_url, connect_timeout: 0.2, read_timeout: 0.2)
      client.ping
      { "ok" => true }
    rescue Redis::BaseError, RedisClient::Error => e
      failed(e)
    ensure
      client&.close
    end

    def sidekiq
      Sidekiq.redis { |conn| conn.ping }
      { "ok" => true, "workers" => Sidekiq::ProcessSet.new.size }
    rescue Redis::BaseError, RedisClient::Error => e
      failed(e)
    end

    def failed(error)
      # Public payload gets the exception class, not the message (hosts/ports leak). Full message is logged. See SOLUTION.md.
      Rails.logger.warn("health check #{error.class}: #{error.message}")
      { "ok" => false, "error" => error.class.name }
    end

    def redis_url
      ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
    end
  end
end
