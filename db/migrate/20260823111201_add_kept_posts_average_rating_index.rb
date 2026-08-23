# frozen_string_literal: true

class AddKeptPostsAverageRatingIndex < ActiveRecord::Migration[8.1]
  # Concurrent so a live table stays readable. See SOLUTION.md.
  disable_ddl_transaction!

  def change
    add_index :posts, [ :average_rating, :created_at ],
      order: { created_at: :desc },
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      name: "index_posts_kept_on_average_rating_created_at"
  end
end
