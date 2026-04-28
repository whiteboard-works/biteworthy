FactoryBot.define do
  factory :point do
    user_id { 1 }
    object_id { 1 }
    object_class { "MyString" }
    change_type { 1 }
    worth { 1 }
  end
end
