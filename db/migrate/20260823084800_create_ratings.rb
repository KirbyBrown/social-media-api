# frozen_string_literal: true

class CreateRatings < ActiveRecord::Migration[8.1]
  def change
    create_table :ratings do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :post, null: false, foreign_key: true
      t.integer :value, null: false

      t.timestamps
    end

    add_index :ratings, [ :user_id, :post_id ], unique: true
  end
end
