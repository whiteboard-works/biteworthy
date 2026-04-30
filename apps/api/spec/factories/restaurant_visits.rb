FactoryBot.define do
  factory :restaurant_visit do
    user
    restaurant
    viewed_on { Date.current }
    items_visible_count { 5 }
    items_hidden_count  { 2 }
  end
end
