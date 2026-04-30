FactoryBot.define do
  # Real-ish review snippets so spec output reads like menu data.
  REVIEW_BODIES = [
    "Best taco I've had in town.",
    "Ran a little spicy for me but flavor was on point.",
    "Bun was a bit dry, otherwise solid.",
    "Salmon was perfectly cooked.",
    nil # blank body is allowed
  ].freeze

  factory :review do
    user
    item
    rating { rand(3..5) }
    body   { REVIEW_BODIES.sample }
  end
end
