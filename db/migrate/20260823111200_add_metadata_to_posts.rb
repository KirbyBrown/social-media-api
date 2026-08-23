# frozen_string_literal: true

class AddMetadataToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :metadata, :jsonb, null: false, default: {}
  end
end
