# frozen_string_literal: true

module Ratings
  class Upsert
    def initialize(user:, post:, value:)
      @user = user
      @post = post
      @value = value
    end

    def call
      persist
    rescue ActiveRecord::RecordNotUnique
      # First-insert races lose the unique index; retry once as an update. See SOLUTION.md.
      persist
    end

    private

    def persist
      rating = nil

      Rating.transaction do
        # Row lock serializes same-user writers. Redis lock is later, for contention, not correctness. See SOLUTION.md.
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
      end

      rating
    end

    # SQL increment so we do not bump lock_version or run callbacks. See SOLUTION.md.
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
