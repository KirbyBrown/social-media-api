# frozen_string_literal: true

class ChangePostsMetadataGinToPathOps < ActiveRecord::Migration[8.1]
  # Concurrent so a live table stays readable. See SOLUTION.md.
  disable_ddl_transaction!

  def change
    remove_index :posts, :metadata, algorithm: :concurrently
    # jsonb_path_ops: smaller, @> only. jsonb_ops would also serve ? / ?& / ?|. See SOLUTION.md.
    add_index :posts, :metadata, using: :gin, opclass: :jsonb_path_ops, algorithm: :concurrently
  end
end
