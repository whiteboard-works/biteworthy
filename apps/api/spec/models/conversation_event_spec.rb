require "rails_helper"

RSpec.describe ConversationEvent do
  let(:conversation) { create(:conversation) }
  let(:run)          { ConversationRun.acquire(conversation) }

  describe ".append!" do
    # Positions are per conversation, not per run, so a client that
    # watched one turn end and the next begin reads one sequence and can
    # resume from a single cursor.
    it "numbers events monotonically across runs" do
      3.times { |i| described_class.append!(run, { "type" => "text_delta", "text" => i.to_s }) }
      run.release!(outcome: "done")
      described_class.append!(ConversationRun.acquire(conversation), { "type" => "done", "text" => "fin" })

      expect(described_class.where(conversation_id: conversation.id).in_order.pluck(:position)).to eq([ 1, 2, 3, 4 ])
    end

    # The narrator flushes every 80 characters, and the old version took
    # the conversation's row lock for each flush — the same lock
    # `Conversation#append!` takes, so a turn queued behind its own
    # narration. One statement, no lock, is the whole point of the change.
    it "writes one statement and takes no lock on the conversation" do
      run # acquire outside the measurement

      sql = capture_sql { described_class.append!(run, { "type" => "text_delta", "text" => "hi" }) }

      expect(sql.size).to eq(1)
      expect(sql.grep(/FOR UPDATE/)).to be_empty
    end

    it "stores the payload as written" do
      described_class.append!(run, { type: "tool_use", name: "get_menu" })

      expect(described_class.last.payload).to eq({ "type" => "tool_use", "name" => "get_menu" })
    end

    # The position is chosen inside the INSERT, so a loser sees the unique
    # index rather than silently overwriting — and takes the next free
    # position instead of dropping the event.
    it "retries onto the next position when someone else took this one" do
      described_class.create!(conversation: conversation, conversation_run: run,
                              position: 1, payload: { "type" => "open" }, created_at: Time.current)

      expect { described_class.append!(run, { "type" => "done" }) }
        .to change { described_class.where(conversation_id: conversation.id).count }.by(1)
      expect(described_class.where(conversation_id: conversation.id).in_order.pluck(:position)).to eq([ 1, 2 ])
    end
  end
end
