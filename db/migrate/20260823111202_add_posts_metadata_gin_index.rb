# frozen_string_literal: true

class AddPostsMetadataGinIndex < ActiveRecord::Migration[8.1]
  # Concurrent so a live table stays readable. See SOLUTION.md.
  disable_ddl_transaction!

  def change
    add_index :posts, :metadata, using: :gin, algorithm: :concurrently
  end
end
