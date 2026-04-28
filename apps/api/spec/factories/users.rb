FactoryBot.define do
  factory :user do
    sequence(:email)  { |n| "user#{n}@example.com" }
    sequence(:handle) { |n| "user_#{n}" }
    display_name      { "Test User" }
    password          { "password123" }
    password_confirmation { "password123" }

    # Compatibility trait — reserved for when :confirmable comes back
    # in Phase 4. No-op for now.
    trait :confirmed do
    end
  end
end
