# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password
  has_many :posts, dependent: :destroy
  has_many :ratings, dependent: :destroy

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  # Username uniqueness is case-sensitive on purpose. Kirby and kirby can both exist.
  # See SOLUTION.md.
  normalizes :username, with: ->(username) { username.to_s.strip }

  validates :username, presence: true, uniqueness: true, length: { in: 3..30 },
            format: { with: /\A[a-zA-Z0-9_]+\z/, message: "may only contain letters, numbers, and underscores" }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || password.present? }

  def as_public_json
    as_json(only: %i[id username email created_at updated_at])
  end
end
