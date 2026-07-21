require "rails_helper"

RSpec.describe ResolveIngredientsJob, type: :job do
  let(:restaurant) { create(:restaurant, :published) }

  let(:staging_in) do
    {
      "sections" => [
        { "name" => "Tacos", "items" => [
            { "name" => "Carne Asada Taco",
              "description" => "Grilled steak, cilantro, onion, lime.",
              "prices" => [{ "size" => nil, "price_cents" => 450 }] },
            { "name" => "Pollo Taco",
              "description" => "Grilled chicken, cabbage, salsa verde.",
              "prices" => [{ "size" => nil, "price_cents" => 425 }] }
          ] },
        { "name" => "Drinks", "items" => [
            { "name" => "Horchata",
              "description" => "Sweet rice & cinnamon drink.",
              "prices" => [{ "size" => nil, "price_cents" => 350 }] }
          ] }
      ]
    }
  end

  let(:run) do
    create(:ingestion_run, :extracting,
           restaurant: restaurant,
           staging: staging_in)
  end

  let(:resolution_response) do
    {
      "items" => [
        { "index" => 0,
          "resolved" => [{ "slug" => "meat-beef", "confidence" => 0.97 },
                         { "slug" => "vegetable-onion", "confidence" => 0.92 }],
          "unresolved" => [] },
        { "index" => 1,
          "resolved" => [{ "slug" => "poultry-domestic-chicken", "confidence" => 0.95 }],
          "unresolved" => ["salsa verde"] },
        { "index" => 2,
          "resolved" => [{ "slug" => "grain-rice", "confidence" => 0.99 },
                         { "slug" => "spice-cinnamon", "confidence" => 0.88 }],
          "unresolved" => [] }
      ]
    }
  end

  before do
    # The catalog builder pulls from Ingredient.order(:path) — make
    # sure those rows exist so its prompt isn't empty.
    create(:ingredient, slug: "meat-beef")
    create(:ingredient, slug: "vegetable-onion")
    create(:ingredient, slug: "poultry-domestic-chicken")
    create(:ingredient, slug: "grain-rice")
  end

  # ExtractMenuJob now materializes items up front (position = flat index),
  # and the run is at :resolving when the resolve stages run. Mirror that here.
  before do
    pos = 0
    Array(run.staging["sections"]).each do |section|
      Array(section["items"]).each do |it|
        run.ingestion_items.create!(
          name: it["name"], section_name: section["name"], position: pos, decision: "pending"
        )
        pos += 1
      end
    end
    run.transition_to!(:resolving)
  end

  describe "happy path" do
    before do
      allow_any_instance_of(AnthropicClient)
        .to receive(:messages_create).and_return(resolution_response)
    end

    it "writes resolved + unresolved arrays onto the items in place, by position" do
      described_class.perform_now(run.id)

      items = run.ingestion_items.order(:position)
      expect(items[0].ingredients_payload).to contain_exactly(
        { "slug" => "meat-beef", "confidence" => 0.97 },
        { "slug" => "vegetable-onion", "confidence" => 0.92 }
      )
      expect(items[1].ingredients_payload).to eq(
        [{ "slug" => "poultry-domestic-chicken", "confidence" => 0.95 }]
      )
      expect(items[1].unresolved_ingredients).to eq(["salsa verde"])
      expect(items[2].ingredients_payload).to include(
        { "slug" => "grain-rice", "confidence" => 0.99 }
      )
    end

    it "queues ResolveTagsJob and records latency" do
      expect(ResolveTagsJob).to receive(:perform_later).with(run.id)

      described_class.perform_now(run.id)

      run.reload
      expect(run.latency_ms).to be >= 0
    end

    it "runs on the faster resolve model, not the default extraction model" do
      expect(AnthropicClient).to receive(:new)
        .with(model: "claude-haiku-4-5-20251001").and_call_original

      described_class.perform_now(run.id)
    end
  end

  describe "no items in staging" do
    let(:staging_in) { { "sections" => [] } }

    it "fails the run cleanly" do
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      run.reload
      expect(run.failed?).to be true
      expect(run.failure_message).to eq("resolve_ingredients: no_items_in_staging")
    end
  end

  describe "Anthropic API error" do
    before do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ApiError.new(status: 503, body: "down"))
    end

    it "fails the run with status + body context" do
      expect(ResolveTagsJob).not_to receive(:perform_later)

      described_class.perform_now(run.id)

      run.reload
      expect(run.failed?).to be true
      expect(run.failure_message).to start_with("resolve_ingredients_api_error: 503")
    end
  end

  describe "ValidationError" do
    before do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ValidationError.new(
          raw_body: "{}", errors: ["items missing", "shape mismatch"]
        ))
    end

    it "fails the run with the validator's errors" do
      described_class.perform_now(run.id)

      run.reload
      expect(run.failed?).to be true
      expect(run.failure_message).to start_with("resolve_ingredients_validation_failed:")
      expect(run.failure_message).to include("items missing")
    end
  end

  describe "no-op on terminal states" do
    it "does nothing when the run is already :staged / :failed / :published" do
      run.transition_to!(:staged)
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      run.reload
      expect(run.staged?).to be true
    end
  end
end
