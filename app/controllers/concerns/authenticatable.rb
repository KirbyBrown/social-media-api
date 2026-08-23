# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  private

  def current_user
    @current_user ||= user_from_token
  end

  def authenticate_user!
    return if current_user

    render_error(code: "unauthorized", message: "Authentication required", status: :unauthorized)
  end

  def user_from_token
    header = request.authorization.to_s
    token = header.delete_prefix("Bearer ").presence
    return if token.blank?

    payload = Auth::Token.decode(token)
    return if payload.blank?

    User.find_by(id: payload["sub"])
  end
end
