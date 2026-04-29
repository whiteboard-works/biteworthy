FactoryBot.define do
  # Per-process counter to disambiguate Faker-generated emails/handles
  # — Faker repeats values, but the schema requires uniqueness on
  # both columns. The counter is appended to whatever Faker returns.
  sequence(:user_disambig) { |n| n }

  factory :user do
    transient do
      disambig { generate(:user_disambig) }
    end

    email         { "#{Faker::Internet.username(specifier: 5..14, separators: %w[_])}_#{disambig}@#{Faker::Internet.domain_name}" }
    display_name  { Faker::Name.name }
    handle        { "#{Faker::Internet.username(specifier: 4..12, separators: %w[_]).downcase.tr('.', '_')}_#{disambig}" }
    password              { "password123" }
    password_confirmation { "password123" }

    # Compatibility trait — reserved for when :confirmable comes back
    # in Phase 4. No-op for now.
    trait :confirmed do
    end
  end
end
