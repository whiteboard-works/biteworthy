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

  let(:run) do
    r = create(:ingestion_run,
               restaurant: restaurant,
               status:     "resolving",
               staging:    staging_with_ingredients,
               state_history: { "extracting" => 5.minutes.ago.utc.iso8601,
                                "resolving"  => Time.current.utc.iso8601 })
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

    it "writes resolved tags into staging and creates IngestionItems" do
      expect {
        described_class.perform_now(run.id)
      }.to change(IngestionItem, :count).by(2)

      run.reload
      tacos = run.staging["sections"][0]["items"]
      expect(tacos[0]["tags"]).to include({ "slug" => "cuisine-mexican", "confidence" => 0.99 })
      expect(tacos[1]["tags"]).to include({ "slug" => "allergen-contains-dairy", "confidence" => 0.97 })
      expect(tacos[1]["unresolved_tags"]).to eq(["queso-style"])
    end

    it "transitions the run to :staged" do
      described_class.perform_now(run.id)

      run.reload
      expect(run.staged?).to be true
      expect(run.state_history.keys).to include("staged")
    end

    it "materializes the IngestionItems with the right payloads" do
      described_class.perform_now(run.id)

      first_item = IngestionItem.find_by(name: "Carne Asada Taco")
      expect(first_item).to have_attributes(
        ingestion_run:        run,
        section_name:         "Tacos",
        decision:             "pending"
      )
      expect(first_item.ingredients_payload).to eq(
        [{ "slug" => "meat-beef", "confidence" => 0.97 }]
      )
      expect(first_item.tags_payload).to include(
        { "slug" => "cuisine-mexican", "confidence" => 0.99 }
      )
      expect(first_item.prices_payload).to eq(
        [{ "size" => nil, "price_cents" => 450 }]
      )

      cheese = IngestionItem.find_by(name: "Cheese Quesadilla")
      expect(cheese.unresolved_tags).to eq(["queso-style"])
    end
  end

  describe "Anthropic API error" do
    before do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ApiError.new(status: 500, body: "boom"))
    end

    it "fails the run + does not create IngestionItems" do
      expect {
        described_class.perform_now(run.id)
      }.not_to change(IngestionItem, :count)

      run.reload
      expect(run.failed?).to be true
      expect(run.failure_message).to start_with("resolve_tags_api_error: 500")
    end
  end
end
