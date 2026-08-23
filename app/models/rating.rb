# frozen_string_literal: true

class Rating < ApplicationRecord
  belongs_to :user
  belongs_to :post

  validates :value, presence: true, inclusion: { in: 1..5 }
  validates :user_id, uniqueness: { scope: :post_id }

  def as_api_json
    as_json(only: %i[id user_id post_id value created_at updated_at])
  end
end
