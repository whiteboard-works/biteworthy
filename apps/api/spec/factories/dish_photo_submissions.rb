FactoryBot.define do
  factory :dish_photo_submission do
    user
    association :item, factory: [ :item, :published ]
    owns_rights { true }
    status { "pending" }
    credit_name { user.display_name.presence || user.handle }

    after(:build) do |submission|
      next if submission.photo.attached?

      submission.photo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test-image.jpg")),
        filename: "dish.jpg",
        content_type: "image/jpeg"
      )
    end

    trait :approved do
      status { "approved" }
      reviewed_at { Time.current }
      association :reviewed_by, factory: [ :user, :admin ]
    end

    trait :approve_keep do
      status { "approve_keep" }
      reviewed_at { Time.current }
      association :reviewed_by, factory: [ :user, :admin ]
    end

    trait :rejected do
      status { "rejected" }
      rejection_reason { "low_quality" }
      reviewed_at { Time.current }
      association :reviewed_by, factory: [ :user, :admin ]
      after(:create) { |row| row.photo.purge if row.photo.attached? }
    end

    trait :withdrawn do
      status { "withdrawn" }
      after(:create) { |row| row.photo.purge if row.photo.attached? }
    end
  end
end
