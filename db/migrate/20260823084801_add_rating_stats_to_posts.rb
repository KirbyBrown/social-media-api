# frozen_string_literal: true

class AddRatingStatsToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :ratings_count, :integer, null: false, default: 0
    add_column :posts, :ratings_sum, :integer, null: false, default: 0
    add_column :posts, :average_rating, :decimal, precision: 3, scale: 2
  end
end
