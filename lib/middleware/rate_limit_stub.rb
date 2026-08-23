# frozen_string_literal: true

# Stub for the core "implement rate limiting" requirement.
# Real approach: Rack::Attack (or a token-bucket) keyed by IP and user, returning 429
# in the standard error shape. Still a stub; the optional budget went to locking and jobs. See SOLUTION.md.
class RateLimitStub
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  end
end
