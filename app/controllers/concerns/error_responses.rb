# frozen_string_literal: true

module ErrorResponses
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound do
      render_error(code: "not_found", message: "Not found", status: :not_found)
    end

    rescue_from ActionController::ParameterMissing do |error|
      render_error(
        code: "bad_request",
        message: "Missing required parameter: #{error.param}",
        status: :bad_request,
        details: { error.param => [ "is required" ] }
      )
    end

    rescue_from ActiveRecord::StaleObjectError do
      render_error(
        code: "conflict",
        message: "Post was updated by someone else",
        status: :conflict,
        details: { lock_version: [ "is stale" ] }
      )
    end

    rescue_from ActiveRecord::RecordNotUnique do |error|
      render_error(
        code: "validation_failed",
        message: "Validation failed",
        status: :unprocessable_content,
        details: unique_constraint_details(error)
      )
    end

    rescue_from Redis::BaseError, RedisClient::Error do
      render_error(
        code: "unavailable",
        message: "A required dependency is unavailable",
        status: :service_unavailable
      )
    end
  end

  private

  def render_error(code:, message:, status:, details: {})
    render json: { error: { code: code, message: message, details: details } }, status: status
  end

  def render_validation_error(record)
    render_error(
      code: "validation_failed",
      message: "Validation failed",
      status: :unprocessable_content,
      details: record.errors.messages
    )
  end

  def unique_constraint_details(error)
    message = error.message.to_s
    details = {}
    details[:username] = [ "has already been taken" ] if message.include?("username")
    details[:email] = [ "has already been taken" ] if message.include?("email")
    details[:base] = [ "has already been taken" ] if details.empty?
    details
  end
end
