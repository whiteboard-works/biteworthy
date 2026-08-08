require "rails_helper"

# The mutex, the lease, and the stop flag — built out of Postgres because
# there is no Redis in this stack. Each example here is a failure mode that
# had no owner before: two tabs interleaving, a killed worker wedging a
# conversation forever, a stop press arriving mid-turn.
RSpec.describe ConversationRun do
  let(:conversation) { create(:conversation) }

  describe ".acquire" do
    it "hands the lock to one caller" do
      run = described_class.acquire(conversation)

      expect(run).to be_present
      expect(run.state).to eq("running")
      expect(run.lease_expires_at).to be > Time.current
    end

    # The interleaving bug this whole phase exists to close. Two turns on
    # one conversation write into a single ordered message list, and the
    # result is not merely confusing — the Messages API rejects it, which
    # makes the conversation permanently unusable.
    it "refuses a second caller while the first still holds it" do
      described_class.acquire(conversation)

      expect(described_class.acquire(conversation)).to be_nil
    end

    # Postgres aborts the whole transaction on a constraint violation, so
    # a losing acquire inside an enclosing transaction would leave that
    # transaction dead and every later statement in it failing. The
    # savepoint keeps the rollback local to the insert.
    it "loses cleanly inside a caller's transaction, leaving it usable" do
      described_class.acquire(conversation)

      ApplicationRecord.transaction do
        expect(described_class.acquire(conversation)).to be_nil
        expect { conversation.update!(title: "still writable") }.not_to raise_error
      end

      expect(conversation.reload.title).to eq("still writable")
    end

    it "lets a different conversation run at the same time" do
      described_class.acquire(conversation)

      expect(described_class.acquire(create(:conversation))).to be_present
    end

    # Without this a container killed mid-turn holds the lock forever and
    # the user can never speak in that conversation again.
    it "steals a lease that has lapsed" do
      dead = described_class.acquire(conversation)
      dead.update!(lease_expires_at: 1.second.ago)

      stolen = described_class.acquire(conversation)

      expect(stolen).to be_present
      expect(stolen.run_token).not_to eq(dead.run_token)
      expect(described_class.running.where(conversation_id: conversation.id).count).to eq(1)
    end

    # The dead run asked to be stopped; the turn that replaces it did not.
    # Carrying the flag across would kill a turn the user never stopped.
    it "clears the dead run's stop flag when it steals" do
      dead = described_class.acquire(conversation)
      dead.update!(lease_expires_at: 1.second.ago, abort_requested_at: Time.current)

      expect { described_class.acquire(conversation).tick! }.not_to raise_error
    end
  end

  describe "#tick!" do
    it "pushes the lease out so a long turn keeps its lock" do
      run = described_class.acquire(conversation)
      run.update!(lease_expires_at: 5.seconds.from_now)

      run.tick!

      expect(run.reload.lease_expires_at).to be > 60.seconds.from_now
    end

    # The run has been replaced. It must stop writing immediately rather
    # than clobbering the transcript of the turn that took over.
    it "raises LostLease once the lock has been stolen" do
      run = described_class.acquire(conversation)
      run.update!(lease_expires_at: 1.second.ago)
      described_class.acquire(conversation)

      expect { run.tick! }.to raise_error(described_class::LostLease)
    end

    it "raises Aborted when the user pressed stop" do
      run = described_class.acquire(conversation)
      described_class.where(id: run.id).update_all(abort_requested_at: Time.current)

      expect { run.tick! }.to raise_error(described_class::Aborted)
    end

    # Never honour an abort that belongs to an older run. A flag raised
    # against a turn that already ended would otherwise kill the next one
    # the moment it started.
    it "ignores a stop flag raised before this run began" do
      run = described_class.acquire(conversation)
      described_class.where(id: run.id).update_all(abort_requested_at: run.started_at - 1.second)

      expect { run.tick! }.not_to raise_error
    end
  end

  describe "#release!" do
    it "frees the lock so the next turn can take it" do
      run = described_class.acquire(conversation)

      run.release!(outcome: "done")

      expect(run.reload.state).to eq("done")
      expect(run.finished_at).to be_present
      expect(run.duration_ms).to be >= 0
      expect(described_class.acquire(conversation)).to be_present
    end

    # A run that lost its lease is no longer the authority on how this
    # conversation's turn ended.
    it "does not let a replaced run mark its replacement finished" do
      dead = described_class.acquire(conversation)
      dead.update!(lease_expires_at: 1.second.ago)
      live = described_class.acquire(conversation)

      dead.release!(outcome: "done")

      expect(live.reload.state).to eq("running")
    end
  end

  describe "#record_round!" do
    # api_cost_cents answers "are we over budget". This answers "what is
    # the money going to", which is what decides whether tool routing or
    # shorter answers is the lever worth pulling.
    it "accumulates the token split across rounds" do
      run = described_class.acquire(conversation)

      run.record_round!("input_tokens" => 10, "output_tokens" => 5, "cache_read_input_tokens" => 21_650)
      run.record_round!("input_tokens" => 3,  "output_tokens" => 7, "cache_read_input_tokens" => 21_650)

      run.reload
      expect(run.rounds).to eq(2)
      expect(run.input_tokens).to eq(13)
      expect(run.output_tokens).to eq(12)
      expect(run.cache_read_tokens).to eq(43_300)
    end
  end
end
