FactoryBot.define do
  factory :ingestion_run do
    restaurant
    input_kind { "photo" }
    status     { "queued" }
    state_history { {} }

    trait :extracting do
      status        { "extracting" }
      state_history { { "queued" => 5.minutes.ago.utc.iso8601, "extracting" => Time.current.utc.iso8601 } }
    end

    trait :staged do
      status        { "staged" }
      state_history { { "queued" => 5.minutes.ago.utc.iso8601, "staged" => Time.current.utc.iso8601 } }
    end

    trait :failed do
      status         { "failed" }
      failure_message { "Anthropic returned 500: server overloaded" }
    end
  end

  factory :ingestion_item do
    ingestion_run
    sequence(:name) { |n| ["Carne Asada Taco", "Pollo Burrito", "Cheese Quesadilla", "Pad Thai"][n % 4] }
    description { "Grilled steak, cilantro, onion, lime." }
    section_name { "Tacos" }
    decision { "pending" }

    # The shape Phase 2.4's resolve job will write here.
    # IngredientMatcher produces NAME_CONFIDENCE=1.0 or ALIAS_CONFIDENCE=0.95
    ingredients_payload do
      [
        { "slug" => "meat-beef",         "confidence" => 1.0 },
        { "slug" => "vegetable-onion",   "confidence" => 1.0 },
        { "slug" => "herb-cilantro",     "confidence" => 0.95 }
      ]
    end
    tags_payload do
      [{ "slug" => "cuisine-mexican", "confidence" => 1.0 }]
    end
    prices_payload { [{ "size" => nil, "price_cents" => 450 }] }

    trait :pending  do; decision { "pending"  }; end
    trait :rejected do; decision { "rejected" }; end
  end
end
