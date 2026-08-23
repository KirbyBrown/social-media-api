class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false, limit: 100
      t.text :body, null: false
      t.datetime :deleted_at
      t.integer :views_count, null: false, default: 0

      t.timestamps
    end

    add_index :posts, :deleted_at
  end
end
