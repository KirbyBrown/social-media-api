# frozen_string_literal: true

FactoryBot.define do
  factory :rating do
    user
    post
    value { 4 }
  end
end
