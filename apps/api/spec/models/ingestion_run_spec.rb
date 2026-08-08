require "rails_helper"

RSpec.describe IngestionRun, type: :model do
  describe "#transition_to!" do
    it "moves the run forward through the happy-path chain" do
      run = create(:ingestion_run)

      expect { run.transition_to!(:extracting) }
        .to change(run, :status).from("queued").to("extracting")
      run.transition_to!(:resolving)
      run.transition_to!(:staged)
      run.transition_to!(:published)

      expect(run.published?).to be true
    end

    it "is idempotent — re-calling with the current state is a no-op" do
      run = create(:ingestion_run, :extracting)
      original_history = run.state_history.dup

      expect { run.transition_to!(:extracting) }.not_to change(run, :status)
      expect(run.reload.state_history).to eq(original_history)
    end

    it "writes an entry timestamp into state_history once per state" do
      run = create(:ingestion_run)
      run.transition_to!(:extracting)
      first_extracting_at = run.state_history["extracting"]

      # Calling transition_to!(:extracting) a second time must NOT
      # bump the timestamp — first-entry semantics.
      sleep 0.01
      run.transition_to!(:extracting)
      expect(run.state_history["extracting"]).to eq(first_extracting_at)
    end

    it "raises InvalidTransition on a non-adjacent forward move" do
      run = create(:ingestion_run)

      expect { run.transition_to!(:published) }
        .to raise_error(IngestionRun::InvalidTransition, /from "queued" to "published"/)
    end

    it "raises ArgumentError on an unknown state name" do
      run = create(:ingestion_run)
      expect { run.transition_to!(:nonsense) }.to raise_error(ArgumentError)
    end

    # Dispatch used to be hidden in an after-transition hook here, which
    # made `transition_to!(:extracting)` silently fire an Anthropic call.
    # It now lives at the call sites (Ingestion::StartRun / ExtractRun /
    # ReExtractRun) so the pipeline's control flow is readable.
    it "does not enqueue any job — dispatch is the caller's job" do
      run = create(:ingestion_run)

      expect { run.transition_to!(:extracting) }.not_to have_enqueued_job
    end
  end

  describe "#fail!" do
    it "transitions to failed from any state and stores the message" do
      run = create(:ingestion_run, :extracting)

      run.fail!("Anthropic returned 500: server overloaded")

      expect(run.failed?).to be true
      expect(run.failure_message).to eq("Anthropic returned 500: server overloaded")
    end

    it "truncates a wildly long failure message to 2000 chars" do
      run = create(:ingestion_run)
      huge = "x" * 5_000

      run.fail!(huge)

      expect(run.failure_message.length).to eq(2_000)
    end

    it "doesn't enqueue any next-stage job" do
      expect { create(:ingestion_run).fail!("anything") }.not_to have_enqueued_job
    end
  end

  describe "predicate methods" do
    it "exposes a #{IngestionRun::STATUSES.first}? for every status" do
      run = build(:ingestion_run, status: "extracting")
      expect(run.extracting?).to be true
      expect(run.queued?).to     be false
      expect(run.failed?).to     be false
    end
  end

  describe "#record_api_usage! (Phase 6.1.1)" do
    let(:run) { create(:ingestion_run) }

    let(:usage) do
      { "input_tokens" => 100_000, "output_tokens" => 2_000,
        "cache_read_input_tokens" => 50_000, "cache_creation_input_tokens" => 10_000 }
    end

    it "accrues cost + token counts and stamps the model" do
      run.record_api_usage!(usage, model: "claude-sonnet-4-6")

      run.reload
      expect(run.api_cost_cents).to eq(Ingestion::UsageCost.cents(usage, model: "claude-sonnet-4-6"))
      expect(run.cached_input_tokens).to   eq(50_000)
      expect(run.uncached_input_tokens).to eq(110_000) # input + cache writes
      expect(run.model).to eq("claude-sonnet-4-6")
    end

    it "accumulates across calls — three pipeline stages add up, not overwrite" do
      2.times { run.record_api_usage!(usage, model: "claude-sonnet-4-6") }

      expect(run.reload.cached_input_tokens).to eq(100_000)
    end

    it "no-ops on nil usage (stubbed clients, failed calls)" do
      expect { run.record_api_usage!(nil) }.not_to change { run.reload.api_cost_cents }
    end
  end
end
