# frozen_string_literal: true

module Api
  module V1
    class HealthController < ApplicationController
      def show
        result = Health::Check.new.call
        # Postgres down is 503. Redis or Sidekiq down is reported and still 200. See SOLUTION.md.
        render json: result, status: result.http_status
      end
    end
  end
end
