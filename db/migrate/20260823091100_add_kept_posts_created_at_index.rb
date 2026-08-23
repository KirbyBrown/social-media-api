# frozen_string_literal: true

class AddKeptPostsCreatedAtIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :posts, :created_at, order: { created_at: :desc }, where: "deleted_at IS NULL"
  end
end
