# frozen_string_literal: true

module Timeline
  class WarmJob < ApplicationJob
    def perform
      Feed.new.call
    end
  end
end
