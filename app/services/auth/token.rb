# frozen_string_literal: true

module Auth
  class Token
    ALGORITHM = "HS256"
    TTL = 24.hours

    def self.encode(user)
      payload = { sub: user.id, exp: TTL.from_now.to_i }
      JWT.encode(payload, secret, ALGORITHM)
    end

    def self.decode(token)
      payload, = JWT.decode(token, secret, true, { algorithm: ALGORITHM })
      payload
    rescue JWT::DecodeError
      nil
    end

    def self.secret
      Rails.application.secret_key_base
    end
    private_class_method :secret
  end
end
