# frozen_string_literal: true

FactoryBot.define do
  factory :post do
    user
    sequence(:title) { |n| "Post title #{n}" }
    body { "A post body that stays well under the limit." }

    trait :deleted do
      deleted_at { Time.current }
    end
  end
end
