# frozen_string_literal: true

module Ratings
  class Upsert
    def initialize(user:, post:, value:)
      @user = user
      @post = post
      @value = value
    end

    def call
      Locks::RedisLock.new("ratings:post:#{@post.id}").around { write }
    end

    private

    def write
      persist
    rescue ActiveRecord::RecordNotUnique
      # First-insert races lose the unique index; retry once as an update. See SOLUTION.md.
      persist
    end

    def persist
      rating = nil
      wrote = false

      Rating.transaction do
        # Row lock serializes same-user writers. Redis lock is contention relief, not correctness. See SOLUTION.md.
        rating = @user.ratings.lock.find_or_initialize_by(post: @post)
        old_value = rating.value
        inserting = rating.new_record?
        rating.value = @value
        next unless rating.valid?

        rating.save!
        apply_delta(
          delta: inserting ? rating.value : rating.value - old_value,
          count_delta: inserting ? 1 : 0
        )
        wrote = true
      end

      if wrote
        Timeline::Feed.invalidate
        enqueue_notification(rating.id)
      end
      rating
    end

    # Notify is best-effort. The rating already committed; Redis down must not 500. See SOLUTION.md.
    def enqueue_notification(rating_id)
      Ratings::NotifyJob.perform_later(rating_id)
    rescue Redis::BaseError, RedisClient::Error => e
      Rails.logger.warn("rating notification skipped #{e.class}: #{e.message}")
    end

    # update_all skips lock_version and callbacks. increment_counter would not. See SOLUTION.md.
    def apply_delta(delta:, count_delta:)
      return if delta.zero? && count_delta.zero?

      Post.where(id: @post.id).update_all(
        Post.sanitize_sql_array(
          [
            <<~SQL.squish,
              ratings_sum = ratings_sum + ?,
              ratings_count = ratings_count + ?,
              average_rating = CASE
                WHEN ratings_count + ? = 0 THEN NULL
                ELSE (ratings_sum + ?)::numeric / (ratings_count + ?)
              END
            SQL
            delta, count_delta, count_delta, delta, count_delta
          ]
        )
      )
    end
  end
end
