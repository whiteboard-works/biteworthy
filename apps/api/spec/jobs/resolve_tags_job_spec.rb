require "rails_helper"

RSpec.describe ResolveTagsJob, type: :job do
  let(:restaurant) { create(:restaurant, :published) }

  let(:staging_with_ingredients) do
    {
      "sections" => [
        { "name" => "Tacos", "items" => [
            { "name" => "Carne Asada Taco",
              "description" => "Grilled steak, cilantro, onion, lime.",
              "prices" => [{ "size" => nil, "price_cents" => 450 }],
              "ingredients" => [{ "slug" => "meat-beef", "confidence" => 0.97 }],
              "unresolved_ingredients" => [] },
            { "name" => "Cheese Quesadilla",
              "description" => "Melted Oaxacan cheese on flour tortilla.",
              "prices" => [{ "size" => nil, "price_cents" => 600 }],
              "ingredients" => [{ "slug" => "dairy-cheese", "confidence" => 0.99 }],
              "unresolved_ingredients" => [] }
          ] }
      ]
    }
  end

  # ExtractMenuJob materializes items up front; by the time ResolveTagsJob runs,
  # ResolveIngredientsJob has already enriched them with ingredients. Recreate
  # that state: items exist (position + ingredients_payload), tags still empty.
  # let! (eager) so the items exist BEFORE a `change(IngestionItem, :count)`
  # block measures the job — the job must not create new items.
  let!(:run) do
    r = create(:ingestion_run,
               restaurant: restaurant, status: "resolving",
               staging:    staging_with_ingredients,
               state_history: { "extracting" => 5.minutes.ago.utc.iso8601,
                                "resolving"  => Time.current.utc.iso8601 })
    pos = 0
    Array(staging_with_ingredients["sections"]).each do |section|
      Array(section["items"]).each do |it|
        r.ingestion_items.create!(
          name:                   it["name"],
          section_name:           section["name"],
          position:               pos,
          prices_payload:         Array(it["prices"]),
          ingredients_payload:    Array(it["ingredients"]),
          unresolved_ingredients: Array(it["unresolved_ingredients"]),
          image_bbox:             it["image_bbox"],
          decision:               "pending"
        )
        pos += 1
      end
    end
    r
  end

  let(:tag_response) do
    {
      "items" => [
        { "index" => 0,
          "resolved" => [
            { "slug" => "cuisine-mexican", "confidence" => 0.99 },
            { "slug" => "prep-grilled",    "confidence" => 0.95 }
          ],
          "unresolved" => [] },
        { "index" => 1,
          "resolved" => [
            { "slug" => "cuisine-mexican",         "confidence" => 0.99 },
            { "slug" => "allergen-contains-dairy", "confidence" => 0.97 }
          ],
          "unresolved" => ["queso-style"] }
      ]
    }
  end

  before do
    create(:tag, slug: "cuisine-mexican")
    create(:tag, slug: "prep-grilled")
    create(:tag, slug: "allergen-contains-dairy")
  end

  describe "happy path" do
    before do
      allow_any_instance_of(AnthropicClient)
        .to receive(:messages_create).and_return(tag_response)
    end

    it "enriches the existing items with tags in place (by position) — no new items" do
      expect {
        described_class.perform_now(run.id)
      }.not_to change(IngestionItem, :count)

      items = run.ingestion_items.order(:position)
      expect(items[0].tags_payload).to include({ "slug" => "cuisine-mexican", "confidence" => 0.99 })
      expect(items[1].tags_payload).to include({ "slug" => "allergen-contains-dairy", "confidence" => 0.97 })
      expect(items[1].unresolved_tags).to eq(["queso-style"])
      # Ingredients from the prior stage are preserved.
      expect(items[0].ingredients_payload).to eq([{ "slug" => "meat-beef", "confidence" => 0.97 }])
    end

    it "transitions the run to :staged" do
      described_class.perform_now(run.id)

      run.reload
      expect(run.staged?).to be true
      expect(run.state_history.keys).to include("staged")
    end
  end

  describe "deferred accepts (accepted while enrichment was running)" do
    before do
      allow_any_instance_of(AnthropicClient)
        .to receive(:messages_create).and_return(tag_response)
      # promote! needs the ingredient rows to build the joins.
      create(:ingredient, slug: "meat-beef")
    end

    it "promotes items accepted during resolving once they're enriched, at :staged" do
      # Accepted while :resolving — recorded but NOT promoted (empty payloads then).
      accepted = run.ingestion_items.order(:position).first
      accepted.update!(decision: "accepted", decided_at: Time.current)
      expect(accepted.item_id).to be_nil

      expect {
        described_class.perform_now(run.id)
      }.to change(Item, :count).by(1)

      accepted.reload
      expect(accepted.item_id).to be_present
      # Safety property: the promoted Item carries the ingredient it was enriched
      # with — nothing goes live without its allergen data.
      expect(accepted.item.ingredients.pluck(:slug)).to include("meat-beef")
    end

    it "auto-publishes when the pre-accepted items cross the 80% threshold at :staged" do
      run.ingestion_items.find_each { |i| i.update!(decision: "accepted", decided_at: Time.current) }

      described_class.perform_now(run.id)

      run.reload
      expect(run.published?).to be true
    end
  end

  describe "Anthropic API error" do
    before do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ApiError.new(status: 500, body: "boom"))
    end

    it "fails the run and leaves the items un-enriched (tags still empty)" do
      described_class.perform_now(run.id)

      run.reload
      expect(run.failed?).to be true
      expect(run.failure_message).to start_with("resolve_tags_api_error: 500")
      expect(run.ingestion_items.first.tags_payload).to eq([])
    end
  end
end
