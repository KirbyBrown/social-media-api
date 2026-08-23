# frozen_string_literal: true

module AuthHelpers
  def auth_headers(user)
    { "Authorization" => "Bearer #{Auth::Token.encode(user)}" }
  end

  def bearer_token(user)
    Auth::Token.encode(user)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers
end
