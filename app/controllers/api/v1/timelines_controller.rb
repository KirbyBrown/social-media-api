# frozen_string_literal: true

module Api
  module V1
    class TimelinesController < ApplicationController
      before_action :authenticate_user!

      def show
        min_rating = parse_min_rating
        return if performed?

        render json: Timeline::Feed.new(page: params[:page], min_rating:).call
      end

      private

      def parse_min_rating
        raw = params[:min_rating]
        return if raw.blank?

        value = Float(raw)
        return value if (1.0..5.0).cover?(value)

        render_bad_min_rating
      rescue ArgumentError, TypeError
        render_bad_min_rating
      end

      def render_bad_min_rating
        render_error(
          code: "bad_request",
          message: "min_rating must be between 1 and 5",
          status: :bad_request,
          details: { min_rating: [ "must be between 1 and 5" ] }
        )
      end
    end
  end
end
