# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  include Sidekiq::Job::Options unless respond_to?(:sidekiq_options)

  # Sidekiq retries 5 times, then the job lands in the dead set. ActiveJob retry_on is off on purpose. See SOLUTION.md.
  sidekiq_options retry: 5

  discard_on ActiveJob::DeserializationError
end
