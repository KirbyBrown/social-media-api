# frozen_string_literal: true

module Posts
  class IncrementViewsJob < ApplicationJob
    # update_all skips lock_version. increment_counter does not, once locking is on. See SOLUTION.md.
    # At-least-once: a retry after a successful increment can double-count. See SOLUTION.md.
    def perform(post_id)
      Post.where(id: post_id).update_all("views_count = views_count + 1")
    end
  end
end
