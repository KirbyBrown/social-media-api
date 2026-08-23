# frozen_string_literal: true

require Rails.root.join("lib/middleware/rate_limit_stub")

Rails.application.config.middleware.use RateLimitStub
