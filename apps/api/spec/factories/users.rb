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

    trait :admin do
      is_admin { true }
    end

    # `is_admin` comes along because the `super_admin_implies_admin`
    # CHECK constraint requires it — a factory that set only the super
    # bit would fail to insert.
    trait :super_admin do
      is_admin           { true }
      is_super_admin     { true }
      skip_confirmations { true }
    end
  end
end
