FactoryBot.define do
  factory :user_item_override do
    user
    item
    never_hide { true }
  end
end
