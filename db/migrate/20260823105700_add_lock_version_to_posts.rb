# frozen_string_literal: true

class AddLockVersionToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :lock_version, :integer, null: false, default: 0
  end
end
