# frozen_string_literal: true

redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

Sidekiq.default_job_options = { "retry" => 5 }
Sidekiq.configure_client { |config| config.redis = redis }
Sidekiq.configure_server { |config| config.redis = redis }
