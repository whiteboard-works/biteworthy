require "rails_helper"

RSpec.describe ExtractMenuJob, type: :job do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, restaurant: restaurant) }

  let(:happy_extraction) do
    {
      "sections" => [
        {
          "name" => "Tacos",
          "items" => [
            { "name" => "Carne Asada Taco",
              "description" => "Grilled steak, cilantro, onion, lime.",
              "prices" => [{ "size" => nil, "price_cents" => 450 }] }
          ]
        }
      ]
    }
  end

  # Attach a tiny fake JPEG. AnthropicClient is mocked everywhere, so
  # the bytes never actually get sent up — it just needs SOMETHING for
  # the job's blobs.empty? check to be false.
  def attach_fake_input!
    run.inputs.attach(
      io:           StringIO.new("\xFF\xD8\xFF\xE0".b),
      filename:     "menu_page1.jpg",
      content_type: "image/jpeg"
    )
  end

  describe "happy path" do
    before do
      attach_fake_input!
      allow_any_instance_of(AnthropicClient)
        .to receive(:messages_create).and_return(happy_extraction)
    end

    it "writes the extraction to staging and transitions to :resolving" do
      described_class.perform_now(run.id)

      run.reload
      expect(run.staging).to eq(happy_extraction)
      expect(run.status).to  eq("resolving")
      expect(run.latency_ms).to be >= 0
      expect(run.state_history.keys).to include("extracting", "resolving")
    end

    it "materializes an IngestionItem per extracted dish up front (empty payloads) for instant review" do
      described_class.perform_now(run.id)

      item = run.ingestion_items.sole
      expect(item).to have_attributes(
        name: "Carne Asada Taco", section_name: "Tacos", position: 0, decision: "pending"
      )
      expect(item.prices_payload).to eq([{ "size" => nil, "price_cents" => 450 }])
      # Enrichment fills these in the background — empty now so the dish shows immediately.
      expect(item.ingredients_payload).to eq([])
      expect(item.tags_payload).to eq([])
    end

    it "is a no-op on already-staged runs" do
      run.update!(status: "staged")
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      run.reload
      expect(run.status).to eq("staged")
    end

    it "accrues real cost + tokens from the call's usage (Phase 6.1.1)" do
      usage = { "input_tokens" => 100_000, "output_tokens" => 2_000,
                "cache_read_input_tokens" => 0, "cache_creation_input_tokens" => 0 }
      allow_any_instance_of(AnthropicClient).to receive(:last_usage).and_return(usage)

      described_class.perform_now(run.id)

      run.reload
      expect(run.api_cost_cents).to be > 0
      expect(run.uncached_input_tokens).to eq(100_000)
      expect(run.model).to eq(AnthropicClient::DEFAULT_MODEL)
    end
  end

  # Phase 4.11.2 — image_bbox handling moved here (materialize is now at
  # extraction). promote! later reads it to crop + attach the inline dish photo.
  describe "image_bbox from extraction" do
    let(:extraction_with_bbox) do
      {
        "sections" => [
          { "name" => "Appetizers", "items" => [
              { "name" => "Spring Rolls", "description" => "Crispy veggie.",
                "prices" => [{ "size" => nil, "price_cents" => 600 }],
                "image_bbox" => { "x" => 0.1, "y" => 0.2, "w" => 0.3, "h" => 0.25 } },
              { "name" => "Tom Yum", "description" => "Hot + sour soup.",
                "prices" => [{ "size" => nil, "price_cents" => 800 }] }
            ] }
        ]
      }
    end

    before do
      attach_fake_input!
      allow_any_instance_of(AnthropicClient)
        .to receive(:messages_create).and_return(extraction_with_bbox)
    end

    it "copies image_bbox onto the item when present, leaves nil otherwise" do
      described_class.perform_now(run.id)

      expect(run.ingestion_items.find_by(name: "Spring Rolls").image_bbox)
        .to eq("x" => 0.1, "y" => 0.2, "w" => 0.3, "h" => 0.25)
      expect(run.ingestion_items.find_by(name: "Tom Yum").image_bbox).to be_nil
    end
  end

  describe "no inputs attached" do
    it "fails the run with the no_inputs_attached message" do
      # No attach_fake_input! call — this test is the one that exercises
      # the empty-blobs path.
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      run.reload
      expect(run.failed?).to be true
      expect(run.failure_message).to eq("no_inputs_attached")
    end
  end

  describe "Anthropic API error" do
    before do
      attach_fake_input!
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ApiError.new(
          status: 500, body: '{"error":"overloaded"}'
        ))
    end

    it "fails the run with status + body context" do
      described_class.perform_now(run.id)

      run.reload
      expect(run.failed?).to be true
      expect(run.failure_message).to start_with("anthropic_api_error: 500")
      expect(run.failure_message).to include("overloaded")
    end
  end

  describe "schema validation failure" do
    before do
      attach_fake_input!
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ValidationError.new(
          raw_body: '{"sections": "not an array"}',
          errors:   ["sections must be an array", "items missing"]
        ))
    end

    it "fails the run with the first few validator errors" do
      described_class.perform_now(run.id)

      run.reload
      expect(run.failed?).to be true
      expect(run.failure_message).to start_with("schema_validation_failed:")
      expect(run.failure_message).to include("sections must be an array")
    end

    it "still accrues the billed usage (Phase 6.1.2 — a 200 that fails our schema cost money)" do
      usage = { "input_tokens" => 100_000, "output_tokens" => 2_000 }
      allow_any_instance_of(AnthropicClient).to receive(:last_usage).and_return(usage)

      described_class.perform_now(run.id)

      run.reload
      expect(run.failed?).to be true
      expect(run.api_cost_cents).to be > 0
    end
  end

  describe "live-cassette integration smoke test" do
    # Phase 4.11.0 / 4.11.2-cassette — replays a real Anthropic
    # vision call against the committed sample.jpg fixture (Simply
    # Tasty Thai appetizers page). Recorded once locally with
    # ANTHROPIC_API_KEY set; CI replays from the committed cassette
    # with `record: :none` (see spec/support/vcr.rb).
    #
    # VCR matches on method + URI + body, so changing the prompt
    # (Phase 4.11.2's image_bbox addition) auto-invalidates the
    # cassette — re-record locally + commit the new file.
    #
    # The mocked specs above are sufficient for the job's branch
    # logic; this is the integration smoke that asserts our prompt +
    # schema actually work against the real model.
    let(:menu_path) { Rails.root.join("spec/fixtures/menus/sample.jpg") }

    let(:run_with_real_image) do
      r = create(:ingestion_run, restaurant: restaurant)
      r.inputs.attach(
        io:           File.open(menu_path, "rb"),
        filename:     "sample.jpg",
        content_type: "image/jpeg"
      )
      r
    end

    it "extracts a real menu image end-to-end", vcr: { cassette_name: "extract_menu_job/simply_tasty_thai_appetizers" } do
      described_class.perform_now(run_with_real_image.id)

      run = run_with_real_image.reload
      expect(run.status).to eq("resolving")
      expect(run.staging).to be_a(Hash)
      expect(run.staging["sections"]).to be_an(Array)
      expect(run.staging["sections"]).not_to be_empty

      # Phase 4.11.2 acceptance: at least 3 items should carry an
      # image_bbox after the prompt extension lands. Simply Tasty
      # Thai's appetizers page has Spring Rolls, Crab Rangoon, and
      # Chicken Satay all with inline photos.
      items = run.staging["sections"].flat_map { |s| s["items"] }
      bbox_items = items.select { |i| i["image_bbox"].present? }
      expect(items.size).to be >= 3
      expect(bbox_items.size).to be >= 3
    end
  end
end
