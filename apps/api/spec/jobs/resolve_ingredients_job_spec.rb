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

  # Move the run to :resolving so transition_to! doesn't fail
  # (transition queued → resolving is invalid).
  before { run.transition_to!(:resolving) }

  describe "happy path" do
    before do
      allow_any_instance_of(AnthropicClient)
        .to receive(:messages_create).and_return(resolution_response)
    end

    it "writes resolved + unresolved arrays back into staging" do
      described_class.perform_now(run.id)

      run.reload
      tacos = run.staging["sections"][0]["items"]
      expect(tacos[0]["ingredients"]).to contain_exactly(
        { "slug" => "meat-beef", "confidence" => 0.97 },
        { "slug" => "vegetable-onion", "confidence" => 0.92 }
      )
      expect(tacos[1]["ingredients"]).to eq(
        [{ "slug" => "poultry-domestic-chicken", "confidence" => 0.95 }]
      )
      expect(tacos[1]["unresolved_ingredients"]).to eq(["salsa verde"])

      drinks = run.staging["sections"][1]["items"]
      expect(drinks[0]["ingredients"]).to include(
        { "slug" => "grain-rice", "confidence" => 0.99 }
      )
    end

    it "queues ResolveTagsJob and records latency" do
      expect(ResolveTagsJob).to receive(:perform_later).with(run.id)

      described_class.perform_now(run.id)

      run.reload
      expect(run.latency_ms).to be >= 0
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
