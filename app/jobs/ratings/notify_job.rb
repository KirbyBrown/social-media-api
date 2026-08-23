# frozen_string_literal: true

module Ratings
  class NotifyJob < ApplicationJob
    def perform(rating_id)
      rating = Rating.find_by(id: rating_id)
      return if rating.blank?

      # Stub: real approach is a mailer or push provider, with this job as the retry boundary. See SOLUTION.md.
      Rails.logger.info("rating notification stub rating_id=#{rating.id} value=#{rating.value}")
    end
  end
end
