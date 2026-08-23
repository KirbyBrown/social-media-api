# frozen_string_literal: true

class Post < ApplicationRecord
  belongs_to :user
  has_many :ratings, dependent: :destroy

  TITLE_MAX = 100
  BODY_MAX = 1000

  scope :kept, -> { where(deleted_at: nil) }

  validates :title, presence: true, length: { maximum: TITLE_MAX }
  validates :body, presence: true, length: { maximum: BODY_MAX }

  def soft_delete
    touch(:deleted_at)
  end

  def kept?
    deleted_at.nil?
  end

  def as_api_json
    as_json(only: %i[id title body views_count ratings_count average_rating created_at updated_at]).merge(
      "user" => user.as_public_json
    )
  end
end
