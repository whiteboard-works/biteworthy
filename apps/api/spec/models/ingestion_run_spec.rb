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

    it "fires Solid Queue jobs registered in JOB_FOR (when their classes exist)" do
      stub_const("ExtractMenuJob", Class.new do
        def self.perform_later(*); end
      end)

      run = create(:ingestion_run)
      expect(ExtractMenuJob).to receive(:perform_later).with(run.id)

      run.transition_to!(:extracting)
    end

    it "is a no-op on the job dispatch when the class doesn't exist" do
      # Sanity: NEXT_STATE for :staged → :published has no JOB_FOR
      # entry, so reaching :published shouldn't try to dispatch.
      run = create(:ingestion_run, :staged)
      expect { run.transition_to!(:published) }.not_to raise_error
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
      stub_const("ExtractMenuJob", Class.new do
        def self.perform_later(*); end
      end)
      expect(ExtractMenuJob).not_to receive(:perform_later)

      create(:ingestion_run).fail!("anything")
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
end
