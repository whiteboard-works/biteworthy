require "rails_helper"

RSpec.describe GapFillResolveJob, type: :job do
  # The attempt retry_on gives up after — the only one that may stamp
  # `failed`, because clients stop waiting on it. retry_on swallows the
  # error once attempts are exhausted, so this returns normally.
  def final_attempt(run_id)
    job = described_class.new(run_id)
    job.executions = ApplicationJob::RETRY_ATTEMPTS - 1
    job.perform_now
  end

  let(:restaurant) { create(:restaurant, :published) }
  let(:run) do
    create(:ingestion_run, :staged, restaurant: restaurant, enrichment_status: "pending")
  end

  before do
    create(:ingredient, slug: "meat-beef") # alias: steak
    create(:ingredient, slug: "fish-anchovy", name: "Anchovy", path: "fish.anchovy", aliases: [])
    create(:tag, slug: "italian", name: "Italian", family: "cuisine", path: "cuisine.italian")
  end

  # As ResolveItemsJob leaves a gap item: pending, empty payloads.
  let!(:gap_item) do
    create(:ingestion_item, ingestion_run: run, position: 0, name: "Caesar Salad",
           description: nil, decision: "pending",
           ingredients_payload: [], tags_payload: [])
  end

  # Fully matched by the deterministic pass — must not be re-sent.
  let!(:matched_item) do
    create(:ingestion_item, ingestion_run: run, position: 1, name: "Steak",
           description: "steak", decision: "pending",
           ingredients_payload: [{ "slug" => "meat-beef", "confidence" => 0.95, "source" => "match" }],
           tags_payload: [])
  end

  let(:response) do
    { "items" => [
      { "index" => 0,
        "ingredients" => {
          "resolved" => [
            { "slug" => "fish-anchovy", "confidence" => 0.85 },
            { "slug" => "not-a-real-slug", "confidence" => 0.9 },
          ],
          "unresolved" => ["romaine hearts"] } },
    ] }
  end

  describe "the merge" do
    before do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create).and_return(response)
      allow(Rails.logger).to receive(:warn)
    end

    it "appends validated AI ingredients, dropping unknown slugs" do
      described_class.perform_now(run.id)

      payload = gap_item.reload.ingredients_payload
      expect(payload).to contain_exactly(
        { "slug" => "fish-anchovy", "confidence" => 0.85, "source" => "ai" }
      )
      expect(Rails.logger).to have_received(:warn).with(/not-a-real-slug/)
    end

    it "leaves the re-scan match columns alone (its upsert must not clobber the matcher)" do
      target = create(:item, restaurant: restaurant, name: "Caesar Salad")
      gap_item.update!(matched_item_id: target.id, match_score: 1.0)

      described_class.perform_now(run.id)

      gap_item.reload
      expect(gap_item.matched_item_id).to eq(target.id)
      expect(gap_item.match_score).to eq(1.0)
    end

    it "re-derives allergen tags in code from the AI ingredients; Haiku has no tag channel at all" do
      described_class.perform_now(run.id)

      tags = gap_item.reload.tags_payload
      expect(tags).to include(
        { "slug" => "contains-fish", "confidence" => 0.85,
          "source" => "ingredient_derived", "from_source" => "ai" }
      )
      # Cuisine is Jev's family; with no JEV_API_KEY in the test env the
      # item carries no AI cuisine row rather than one Haiku made up.
      expect(tags.map { |t| t["source"] }).not_to include("ai")
    end

    it "preserves human-authored tag rows (Undo returns edited items to pending)" do
      gap_item.update!(tags_payload: [
        { "slug" => "contains-peanut", "confidence" => 1.0 },              # human, no source
        { "slug" => "grilled", "confidence" => 0.9, "source" => "match" }, # machine
      ])

      described_class.perform_now(run.id)

      tags = gap_item.reload.tags_payload
      expect(tags).to include({ "slug" => "contains-peanut", "confidence" => 1.0 })
      # Machine rows are rebuilt from the merged ingredient set — "grilled"
      # has no keyword support on this item, so it drops out.
      expect(tags.map { |t| t["slug"] }).not_to include("grilled")
    end

    it "records unresolved ingredient strings for the curation queue and leaves unresolved_tags alone" do
      gap_item.update!(unresolved_tags: ["left by an older release"])
      described_class.perform_now(run.id)

      gap_item.reload
      expect(gap_item.unresolved_ingredients).to eq(["romaine hearts"])
      # Jev answers over the cuisine catalog, so gap-fill has no cuisine
      # phrases to record and must not clear what another writer left.
      expect(gap_item.unresolved_tags).to eq(["left by an older release"])
    end

    it "marks enrichment completed and leaves non-gap items untouched" do
      expect { described_class.perform_now(run.id) }
        .not_to change { matched_item.reload.attributes }

      expect(run.reload.enrichment_status).to eq("completed")
    end

    it "only sends gap items to the model" do
      captured = nil
      allow_any_instance_of(AnthropicClient).to receive(:messages_create) do |_, **kwargs|
        captured = kwargs[:messages]
        response
      end

      described_class.perform_now(run.id)

      text = captured.first[:content].first[:text]
      expect(text).to include("Caesar Salad")
      expect(text).not_to include("Steak")
    end

    it "skips an item that got accepted after the gap set was computed" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create) do
        gap_item.update!(decision: "accepted")
        response
      end

      described_class.perform_now(run.id)

      expect(gap_item.reload.ingredients_payload).to eq([])
      expect(run.reload.enrichment_status).to eq("completed")
    end
  end

  describe "the diet-claim gate on model rows" do
    before do
      create(:ingredient, slug: "grain-wheat", name: "Wheat", path: "grain.wheat", aliases: [])
    end

    # Gap via the composed-dish keyword; the name carries the claim.
    let!(:gf_item) do
      create(:ingestion_item, ingestion_run: run, position: 2, name: "Gluten-Free Pizza",
             description: nil, decision: "pending",
             ingredients_payload: [], tags_payload: [])
    end

    it "drops a returned base that contradicts the name's claim (the prompt asks for 'pizza implies crust')" do
      response = { "items" => [
        { "index" => 1,
          "ingredients" => {
            "resolved" => [
              { "slug" => "grain-wheat", "confidence" => 0.9 },
              { "slug" => "fish-anchovy", "confidence" => 0.85 },
            ],
            "unresolved" => [] } },
      ] }
      allow_any_instance_of(AnthropicClient).to receive(:messages_create).and_return(response)
      allow(Rails.logger).to receive(:info)

      described_class.perform_now(run.id)

      payload = gf_item.reload.ingredients_payload
      expect(payload.map { |r| r["slug"] }).to contain_exactly("fish-anchovy")
      # The claim stays viable end to end: no contains-gluten, so the
      # gluten-free tag survives the rebuild.
      tags = gf_item.tags_payload.map { |t| t["slug"] }
      expect(tags).to include("gluten-free")
      expect(tags).not_to include("contains-gluten")
    end
  end

  describe "chunking" do
    let!(:mysteries) do
      Array.new(26) do |i|
        create(:ingestion_item, ingestion_run: run, position: 2 + i,
               name: format("Mystery Dish %02d", i), description: nil, decision: "pending",
               ingredients_payload: [], tags_payload: [])
      end
    end

    let(:slice_responses) do
      [
        { "items" => [{ "index" => 0,
                        "ingredients" => { "resolved" => [{ "slug" => "fish-anchovy", "confidence" => 0.85 }],
                                           "unresolved" => [] } }] },
        { "items" => [{ "index" => 0,
                        "ingredients" => { "resolved" => [{ "slug" => "meat-beef", "confidence" => 0.7 }],
                                           "unresolved" => [] } }] },
        { "items" => [{ "index" => 0,
                        "ingredients" => { "resolved" => [{ "slug" => "fish-anchovy", "confidence" => 0.6 }],
                                           "unresolved" => [] } }] },
      ]
    end

    it "makes one call per 10 gap items and merges each slice at its own indexes" do
      prompts = []
      allow_any_instance_of(AnthropicClient).to receive(:messages_create) do |_, **kwargs|
        prompts << kwargs[:messages].first[:content].first[:text]
        slice_responses[prompts.length - 1]
      end

      described_class.perform_now(run.id)

      # 27 gap items total (1 gap_item + 26 mysteries) = 3 slices at 10/batch
      expect(prompts.length).to eq(3)
      expect(prompts.first).to include("[0] Caesar Salad", "[9] Mystery Dish 08")
      expect(prompts.first).not_to include("Mystery Dish 09")
      expect(prompts[1]).to include("[0] Mystery Dish 09", "[9] Mystery Dish 18")
      expect(prompts[2]).to include("[0] Mystery Dish 19", "[6] Mystery Dish 25")

      # index 0 of each response lands on that slice's first item, not the run's.
      expect(gap_item.reload.ingredients_payload)
        .to include({ "slug" => "fish-anchovy", "confidence" => 0.85, "source" => "ai" })
      expect(mysteries[9].reload.ingredients_payload)
        .to include({ "slug" => "meat-beef", "confidence" => 0.7, "source" => "ai" })
      expect(mysteries[19].reload.ingredients_payload)
        .to include({ "slug" => "fish-anchovy", "confidence" => 0.6, "source" => "ai" })
      expect(run.reload.enrichment_status).to eq("completed")
    end

    it "handles large menus (77 items like College Cafe) without token limit errors" do
      # Create 77 gap items total (simulating College Cafe)
      additional_items = Array.new(50) do |i|
        create(:ingestion_item, ingestion_run: run, position: 30 + i,
               name: format("College Item %02d", i), description: nil, decision: "pending",
               ingredients_payload: [], tags_payload: [])
      end

      # 77 items at 10/batch = 8 slices (7 full + 1 partial)
      prompts = []
      allow_any_instance_of(AnthropicClient).to receive(:messages_create) do |_, **kwargs|
        prompts << kwargs[:messages].first[:content].first[:text]
        # Verify max_tokens is set
        expect(kwargs[:max_tokens]).to eq(described_class::GAP_MAX_TOKENS)
        slice_responses.first # return valid response for each slice
      end

      described_class.perform_now(run.id)

      # Should make 8 calls for 77 items at 10/batch
      total_items = 1 + 26 + 50 # gap_item + mysteries + additional_items
      expected_batches = (total_items.to_f / described_class::GAP_BATCH_SIZE).ceil
      expect(prompts.length).to eq(expected_batches)
      expect(run.reload.enrichment_status).to eq("completed")
    end

    it "a failing later slice keeps the merges already landed and retries without giving up yet" do
      calls = 0
      allow_any_instance_of(AnthropicClient).to receive(:messages_create) do
        calls += 1
        raise AnthropicClient::ApiError.new(status: 500, body: "boom") if calls > 1

        slice_responses.first
      end
      allow(Rails.logger).to receive(:error)

      # .new.perform bypasses retry_on so the raise is observable — the
      # soft slice failure must reach retry_on, not silently abandon the
      # remaining slices.
      expect { described_class.new.perform(run.id) }
        .to raise_error(GapFillResolveJob::SliceFailedError)

      expect(gap_item.reload.ingredients_payload)
        .to include({ "slug" => "fish-anchovy", "confidence" => 0.85, "source" => "ai" })
      run.reload
      # Still pending: a retry is coming, so clients must keep waiting.
      expect(run.enrichment_status).to eq("pending")
      expect(run.status).to eq("staged")
    end
  end

  describe "soft failure" do
    it "an early ApiError leaves enrichment pending for the retry" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ApiError.new(status: 500, body: "boom"))
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(run.id)

      expect(run.reload.enrichment_status).to eq("pending")
    end

    it "ApiError on the last attempt marks enrichment failed but the run stays staged" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ApiError.new(status: 500, body: "boom"))
      allow(Rails.logger).to receive(:error)

      final_attempt(run.id)

      run.reload
      expect(run.status).to eq("staged")
      expect(run.enrichment_status).to eq("failed")
      expect(run.failure_message).to be_nil
      # Error is logged multiple times: once in timed_anthropic_call (soft failure),
      # once in the slice failure handler, and once in the final rescue block
      expect(Rails.logger).to have_received(:error).with(/gap_fill_api_error/).at_least(:once)
    end

    it "an unexpected error (transport, bug) on the last attempt marks enrichment failed" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(Faraday::TimeoutError)

      final_attempt(run.id)

      run.reload
      expect(run.status).to eq("staged")
      expect(run.enrichment_status).to eq("failed")
    end

    it "network errors are recorded in enrichment_failure_message for diagnostics" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(Faraday::ConnectionFailed.new("DNS lookup failed"))
      allow(Rails.logger).to receive(:error)

      final_attempt(run.id)

      run.reload
      expect(run.enrichment_status).to eq("failed")
      expect(run.enrichment_failure_message).to include("network error")
      expect(run.enrichment_failure_message).to include("ConnectionFailed")
    end

    it "rate limit (429) errors are recorded with status code" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ApiError.new(status: 429, body: '{"error":"rate_limit"}'))
      allow(Rails.logger).to receive(:error)

      final_attempt(run.id)

      run.reload
      expect(run.enrichment_status).to eq("failed")
      expect(run.enrichment_failure_message).to include("429")
      expect(run.enrichment_failure_message).to include("rate_limit")
    end

    it "timeout errors are recorded with timeout duration" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(Faraday::TimeoutError)
      allow(Rails.logger).to receive(:error)

      final_attempt(run.id)

      run.reload
      expect(run.enrichment_status).to eq("failed")
      expect(run.enrichment_failure_message).to include("timeout")
      expect(run.enrichment_failure_message).to match(/\d+s/)
    end

    it "clears enrichment_failure_message on successful retry after a failure" do
      calls = 0
      allow_any_instance_of(AnthropicClient).to receive(:messages_create) do
        calls += 1
        if calls == 1
          raise Faraday::TimeoutError
        else
          response
        end
      end
      allow(Rails.logger).to receive(:error)

      # First attempt fails and sets enrichment_failure_message
      described_class.perform_now(run.id)
      run.reload
      expect(run.enrichment_status).to eq("pending")
      expect(run.enrichment_failure_message).to include("timeout")

      # Retry succeeds and clears the failure message
      described_class.perform_now(run.id)
      run.reload
      expect(run.enrichment_status).to eq("completed")
      expect(run.enrichment_failure_message).to be_nil
    end

    it "ValidationError still accrues the billed usage" do
      usage = { "input_tokens" => 10_000, "output_tokens" => 100,
                "cache_read_input_tokens" => 0, "cache_creation_input_tokens" => 0 }
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ValidationError.new(raw_body: "x", errors: ["bad"]))
      allow_any_instance_of(AnthropicClient).to receive(:last_usage).and_return(usage)
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now(run.id) }
        .to change { run.reload.uncached_input_tokens }.by(10_000)
    end
  end

  describe "guards" do
    it "completes without an API call when no pending gaps remain" do
      gap_item.update!(decision: "rejected")
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      expect(run.reload.enrichment_status).to eq("completed")
    end

    it "is a no-op when enrichment already completed" do
      run.update!(enrichment_status: "completed")
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      expect { described_class.perform_now(run.id) }
        .not_to change { gap_item.reload.attributes }
    end

    it "a no-op retry after a failure does not launder failed into completed" do
      run.update!(enrichment_status: "failed")
      gap_item.update!(decision: "rejected")
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      expect(run.reload.enrichment_status).to eq("failed")
    end

    it "a retry skips slices already fully enriched instead of re-billing them" do
      run.update!(enrichment_status: "failed")
      gap_item.update!(ingredients_payload: [
        { "slug" => "fish-anchovy", "confidence" => 0.85, "source" => "ai" },
      ])
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      # Every slice accounted for (merged by the previous attempt), so
      # the retry may conclude completed.
      expect(run.reload.enrichment_status).to eq("completed")
    end
  end

  # Jev owns cuisine tags. Whatever it does, the Haiku ingredient merge
  # and the enrichment status must come out exactly as they would without it.
  describe "the Jev cuisine tagger" do
    let(:jev_url) { "https://api.typesafe.ai/v1/systemone" }

    before do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create).and_return(response)
      allow(ENV).to receive(:[]).and_call_original
      allow(Rails.logger).to receive(:warn)
    end

    it "never calls TypeSafe when no key is configured, and says so" do
      allow(ENV).to receive(:[]).with("JEV_API_KEY").and_return(nil)
      jev = stub_request(:post, jev_url)

      described_class.perform_now(run.id)

      expect(jev).not_to have_been_made
      expect(run.reload.enrichment_status).to eq("completed")
      expect(Rails.logger).to have_received(:warn).with(/\[jev_cuisine\] JEV_API_KEY unset/)
    end

    it "asks Jev about the gap items only and stores a yes as an AI cuisine row carrying its probability" do
      allow(ENV).to receive(:[]).with("JEV_API_KEY").and_return("test-key")
      jev = stub_request(:post, jev_url).to_return(
        status: 200,
        body: { model: "jev-1.13.0", answers: { "i0__any" => { "type" => "noul", "noul" => 0.99 }, "i0__italian" => { "type" => "noul", "noul" => 0.93 } },
                usage: { input_tokens: 300 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      described_class.perform_now(run.id)

      expect(jev.with { |req| JSON.parse(req.body)["state"]["items"].map { |i| i["name"] } == [ "Caesar Salad" ] })
        .to have_been_made.once
      expect(gap_item.reload.tags_payload).to include(
        { "slug" => "italian", "confidence" => 0.93, "source" => "ai" }
      )
      expect(matched_item.reload.tags_payload).to eq([])
      expect(run.reload.enrichment_status).to eq("completed")
    end

    it "a failing Jev call leaves the Haiku merge and the completed status untouched, with no AI cuisine" do
      allow(ENV).to receive(:[]).with("JEV_API_KEY").and_return("test-key")
      allow(Rails.error).to receive(:report)
      jev = stub_request(:post, jev_url).to_return(status: 500, body: "{}")

      described_class.perform_now(run.id)

      expect(jev).to have_been_made.at_least_once
      expect(run.reload.enrichment_status).to eq("completed")
      expect(gap_item.reload.ingredients_payload).to include(
        { "slug" => "fish-anchovy", "confidence" => 0.85, "source" => "ai" }
      )
      expect(gap_item.tags_payload.map { |t| t["slug"] }).not_to include("italian")
    end

    # A previous attempt's Jev answer must not be rebuilt from nothing
    # when this attempt's Jev call fails.
    it "a failing Jev call keeps the AI cuisine row an earlier attempt landed" do
      allow(ENV).to receive(:[]).with("JEV_API_KEY").and_return("test-key")
      allow(Rails.error).to receive(:report)
      gap_item.update!(tags_payload: [ { "slug" => "italian", "confidence" => 0.9, "source" => "ai" } ])
      stub_request(:post, jev_url).to_return(status: 500, body: "{}")

      described_class.perform_now(run.id)

      expect(gap_item.reload.tags_payload).to include(
        { "slug" => "italian", "confidence" => 0.9, "source" => "ai" }
      )
    end

    # The retry skip only spares the Haiku call: a slice merged by an
    # earlier attempt whose Jev call failed still gets its cuisine.
    it "a retry asks Jev about an already-enriched slice without re-sending it to Haiku" do
      allow(ENV).to receive(:[]).with("JEV_API_KEY").and_return("test-key")
      gap_item.update!(ingredients_payload: [ { "slug" => "fish-anchovy", "confidence" => 0.85, "source" => "ai" } ])
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)
      jev = stub_request(:post, jev_url).to_return(
        status: 200,
        body: { model: "jev-1.13.0", answers: { "i0__any" => { "type" => "noul", "noul" => 0.99 }, "i0__italian" => { "type" => "noul", "noul" => 0.88 } } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      described_class.perform_now(run.id)

      expect(jev).to have_been_made.once
      gap_item.reload
      expect(gap_item.ingredients_payload).to eq([ { "slug" => "fish-anchovy", "confidence" => 0.85, "source" => "ai" } ])
      expect(gap_item.tags_payload).to include({ "slug" => "italian", "confidence" => 0.88, "source" => "ai" })
      expect(run.reload.enrichment_status).to eq("completed")
    end

    it "switches Jev off for the rest of the attempt after one failure, so an outage costs one timeout" do
      allow(ENV).to receive(:[]).with("JEV_API_KEY").and_return("test-key")
      allow(Rails.error).to receive(:report)
      Array.new(10) do |i|
        create(:ingestion_item, ingestion_run: run, position: 2 + i, name: format("Mystery Dish %02d", i),
               description: nil, decision: "pending", ingredients_payload: [], tags_payload: [])
      end
      # 401 is not retried by the client, so one call is one request.
      jev = stub_request(:post, jev_url).to_return(status: 401, body: "{}")

      described_class.perform_now(run.id)

      # 11 gap items make two Haiku slices; only the first reached Jev.
      expect(jev).to have_been_made.once
      expect(run.reload.enrichment_status).to eq("completed")
    end
  end

  describe "live-cassette integration smoke test" do
    # `apps/api/AGENTS.md` treats a changed Anthropic call without a
    # committed cassette as a P1: CI runs `record: :none`, so a prompt or
    # schema that the real model rejects would fail there as a
    # key-not-set error. The mocked examples above cover the job's branch
    # logic; this replays one real Haiku call to assert the ingredient-only
    # prompt + schema (cuisine moved to Jev) still produce a parseable
    # response. Recorded once locally with ANTHROPIC_API_KEY set; VCR
    # matches on method + URI + body, so changing the prompt invalidates
    # the cassette — re-record locally and commit the new file.
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("JEV_API_KEY").and_return(nil)
      allow(Rails.logger).to receive(:warn)
    end

    it "enriches a real gap item end-to-end", vcr: { cassette_name: "gap_fill_resolve_job/caesar_salad_ingredients_only" } do
      described_class.perform_now(run.id)

      expect(run.reload.enrichment_status).to eq("completed")
      payload = gap_item.reload.ingredients_payload
      ai_rows = payload.select { |r| r["source"] == "ai" }
      # The catalog holds meat-beef and fish-anchovy; a Caesar Salad
      # implies the anchovy, and nothing the model returns may be a slug
      # outside the catalog.
      expect(ai_rows.map { |r| r["slug"] }).to include("fish-anchovy")
      expect(ai_rows.map { |r| r["slug"] }).to all(satisfy { |slug| Ingredient.exists?(slug: slug) })
      expect(gap_item.tags_payload.map { |t| t["source"] }).not_to include("ai")
      expect(run.api_cost_cents).to be > 0
    end
  end
end
