class Conversation < ApplicationRecord
  # `awaiting_confirmation` is the human gate. The loop stops there
  # rather than calling a tool annotated destructive, and the call it
  # wanted to make waits in `pending_tool_call` until the user answers.
  # `awaiting_answers` is the second parked state, and it is a different
  # question from the first: `awaiting_confirmation` asks yes or no about
  # a call the model wants to make, this asks *which one did you mean*.
  # The answer comes back as the id of an option the server wrote down
  # rather than as free text, so nothing downstream rests on reading a
  # typed "the first one" correctly. See `Tools::Meta::AskQuestions`.
  STATES = %w[active awaiting_confirmation awaiting_answers failed].freeze

  belongs_to :user
  has_many :messages, -> { order(:position) }, dependent: :destroy, inverse_of: :conversation
  has_many :runs, class_name: "ConversationRun", dependent: :destroy, inverse_of: :conversation
  has_many :events, class_name: "ConversationEvent", dependent: :destroy, inverse_of: :conversation

  validates :state, inclusion: { in: STATES }
  # The four gates in `Chat::ModePolicy`. Listed there rather than here so
  # the column and the thing that reads it cannot drift.
  validates :chat_mode, inclusion: { in: Chat::ModePolicy::MODES }

  scope :newest_first, -> { order(updated_at: :desc) }

  def awaiting_confirmation? = state == "awaiting_confirmation"
  def awaiting_answers?      = state == "awaiting_answers"

  # Either way of being stopped and owing the person a reply. Anything
  # asking "may another turn start" wants this rather than one of them —
  # the two states differ in what is being asked, not in whether the
  # conversation is free.
  def parked? = awaiting_confirmation? || awaiting_answers?

  # Whether anything that writes has run since the person last spoke.
  #
  # This is what the undo affordance keys off, and it exists because
  # `accept_edits` and `auto` skip the confirmation gate: in those modes
  # the grant is given before the call, so the only lever left is after
  # it. Undo needs no transaction machinery — the transcript already
  # holds the model's own calls and their arguments, so "undo what you
  # just did" is a turn like any other.
  #
  # Read-only is the exception rather than mutating. A tool declaring no
  # annotations, or a name this build does not recognise, counts as
  # writing and the offer appears: failing toward offering to undo
  # something harmless costs a sentence, and failing the other way leaves
  # someone who just watched a destructive call with no way back.
  # `Chat::ModePolicy.read_only?` is the same answer planning mode uses,
  # deliberately — two places deciding "does this write" must not drift.
  #
  # Nothing to undo while parked: the call has not run, and the answer
  # the person owes is yes or no, not a reversal.
  #
  # Tool results are `user`-role messages, so the scan starts at the last
  # user message that is *not* one — otherwise every turn carrying a tool
  # call would look like it began at its own results.
  def mutated_since_last_user_message?
    return false if parked?

    turn  = messages.to_a
    spoke = turn.rindex { |message| message.role == "user" && !message.tool_result? }
    return false if spoke.nil?

    turn[(spoke + 1)..].any? do |message|
      message.tool_uses.any? { |call| !Chat::ModePolicy.read_only?(Tools::Registry.find(call["name"])) }
    end
  end

  # The Anthropic `messages` array for the next request: every stored
  # turn, verbatim. Tool-use, tool-result, and thinking blocks all have
  # to replay exactly — a thinking block's signature is rejected if it
  # was rebuilt rather than echoed.
  #
  # Read once per model call, and a turn is up to twelve of those. Every
  # jsonb blob in the conversation came back on each one — thinking blocks
  # and signatures included — for the sake of the one or two rows we
  # ourselves had just written, which is O(rounds²) bytes off the wire for
  # no new information. So the loaded rows are kept and every write path
  # below keeps them honest rather than the read re-fetching to be sure.
  def transcript
    stored = (@stored_messages ||= messages.reload.to_a)
    stored.map { |m| { role: m.role, content: m.content } } + repair_for(stored.last)
  end

  # The rows this turn already has in hand.
  #
  # `transcript` loads them once per turn and every write path keeps them
  # honest, so anything else that wants to look at this turn's messages
  # should look here rather than asking Postgres again. A `WHERE role =
  # 'user' LIMIT 1` is a cheaper query and a worse one: it is a second
  # round trip for a record already in memory, and the spec guarding this
  # turn's message loads counts round trips, not rows. Falls back to a
  # real load for a caller that reaches this before any model call.
  def loaded_messages = @stored_messages || messages.to_a

  # The first thing the person said, for whoever needs to name this.
  #
  # A `tool_result` is a `user`-role message, so the earliest one is only
  # the person talking if it is not that. It never is in practice — a
  # result cannot precede the call it answers — but the check costs a
  # predicate and the alternative is naming a conversation after a menu
  # payload.
  def opening_question
    opening = loaded_messages.find { |message| message.role == "user" }
    opening&.text unless opening&.tool_result?
  end

  # Locked for the whole insert, not just the position read: two turns
  # racing would otherwise pick the same position, collide on the unique
  # index, and lose one side's message.
  def append!(role:, content:)
    with_lock do
      messages.create!(role: role, content: content, position: next_position).tap do |message|
        @stored_messages&.push(message)
      end
    end
  end

  # Accrued in micro-cents, exactly. `api_cost_cents` is a generated
  # column derived from this one, so there is nothing to keep in step.
  def record_usage!(usage, model:)
    increment!(:api_cost_micro_cents, ::Ingestion::UsageCost.micro_cents(usage, model: model))
  end

  # The queue a turn waits in when one is already running.
  #
  # Deliberately NOT "append the user's message now, run it later": a
  # message inserted into a transcript mid-turn lands in the middle of the
  # running turn's message list, and the running turn would then answer it.
  # The request waits here as data, and the job appends it as a message
  # only once it holds the lock — one serialization point, no race between
  # checking whether a run is active and writing.
  def enqueue_turn!(payload)
    with_lock do
      update!(pending_turns: Array(pending_turns) + [payload.stringify_keys.merge("at" => Time.current.iso8601)])
    end
  end

  # Pops the oldest queued turn, or nil. Locked because the job draining
  # and a controller enqueuing race on the same array.
  def next_pending_turn!
    with_lock do
      queue = Array(pending_turns)
      return nil if queue.empty?

      update!(pending_turns: queue.drop(1))
      queue.first
    end
  end

  def pending_turns? = Array(pending_turns).any?

  # Run at the start of every turn, because the damage a dead turn leaves
  # behind is only visible on the next one.
  #
  # An assistant message with no content blocks replays as a 400 — the
  # Messages API rejects an empty turn outright — so one crashed
  # completion would otherwise wedge the conversation permanently rather
  # than costing it a single answer.
  def heal!
    Message.where(conversation_id: id, role: "assistant")
           .where("content = '[]'::jsonb")
           .delete_all
    # Deletes go around the association, and this runs at the top of every
    # turn — which is also the one moment another process could have
    # written since we last looked. Dropping the cache here is what keeps
    # it a within-turn cache rather than a bet on nobody else existing.
    @stored_messages = nil
  end

  # Writes real `tool_result` messages for calls that never got one.
  #
  # `transcript` already repairs orphans in memory on read, and that stays
  # — it covers the crash we never saw coming. This is for the ones we
  # do: on a known abort, persisting the answer means the record and the
  # replay agree, instead of the transcript looking broken until something
  # reads it through the repair path.
  def answer_orphans!(message)
    last = messages.reload.last
    return if last.nil? || last.role != "assistant"

    orphans = last.tool_uses
    return if orphans.empty?

    append!(
      role: "user",
      content: orphans.map do |call|
        { type: "tool_result", tool_use_id: call["id"], is_error: true,
          content: [{ type: "text", text: message }] }
      end
    )
  end

  private

  # If a turn died between storing the assistant's tool calls and storing
  # their results — a crashed worker, a killed container — the stored
  # transcript ends on an unanswered `tool_use`, and the Messages API
  # rejects that outright. Without this the conversation would be
  # permanently unusable. Answering the orphans in memory (never written
  # back) both makes the request legal and tells the model what happened,
  # so it re-plans rather than assuming the tools ran.
  def repair_for(last)
    return [] unless last&.role == "assistant"

    orphans = last.tool_uses
    return [] if orphans.empty?

    [{ role: "user",
       content: orphans.map do |call|
         { type: "tool_result", tool_use_id: call["id"], is_error: true,
           content: [{ type: "text", text: "Interrupted before this ran. Nothing happened; try again." }] }
       end }]
  end

  # Deliberately not `messages.maximum` — on a loaded association that
  # computes from the in-memory cache, which the loop has already made
  # stale by appending.
  def next_position
    Message.where(conversation_id: id).maximum(:position).to_i + 1
  end
end
