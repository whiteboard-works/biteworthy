FactoryBot.define do
  factory :dietary_profile_ingredient do
    dietary_profile
    ingredient
    rule { "avoid" }
  end

  factory :dietary_profile_tag do
    dietary_profile
    tag
    rule { "avoid" }
  end
end
