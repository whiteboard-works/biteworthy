FactoryBot.define do
  factory :conversation do
    user
    title { "What can I eat here?" }

    # `api_cost_cents` is a generated column now — Postgres derives it
    # from `api_cost_micro_cents`. ActiveRecord does not *reject* a write
    # to it, it **silently drops one**, which is the worse failure: a spec
    # that still passes `api_cost_cents: 200` gets 0 and no error. This
    # transient keeps the readable form at the call site
    # (`spent_cents: 200`) and routes it to the column the ceiling reads.
    transient do
      spent_cents { nil }
    end

    after(:build) do |conversation, evaluator|
      next if evaluator.spent_cents.nil?

      conversation.api_cost_micro_cents = evaluator.spent_cents * 1_000_000
    end
  end
end
