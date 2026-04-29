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

    it "is a no-op on already-staged runs" do
      run.update!(status: "staged")
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      run.reload
      expect(run.status).to eq("staged")
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
  end

  describe "live-cassette integration smoke test" do
    # Phase 2.3 stop condition (per docs/plans/phase-2.md): cassette
    # recording requires ANTHROPIC_API_KEY which the autonomous loop
    # doesn't have. A human with the key should:
    #   1. Drop a real menu image at spec/fixtures/menus/sample.jpg
    #   2. ANTHROPIC_API_KEY=... bin/rspec spec/jobs/extract_menu_job_spec.rb
    #   3. Commit the recorded cassette under spec/cassettes/
    #   4. Replace this skip block with the VCR.use_cassette block.
    #
    # The mocked specs above are sufficient to validate the job's
    # behavior — this stub is the integration smoke that asserts our
    # prompt + schema actually work against the real model.
    it "extracts a real menu image end-to-end" do
      skip "needs ANTHROPIC_API_KEY + recorded cassette (see comment)"
    end
  end
end
