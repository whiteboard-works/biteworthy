# frozen_string_literal: true

# One attempt at one turn — and the mutex that stops two of them running
# on the same conversation at once.
#
# There is no Redis in this stack (one VM, Neon Postgres, Solid Queue), so
# the primitives are Postgres ones:
#
#   * the **lock** is a partial unique index on `conversation_id WHERE
#     state = 'running'`, so a second `INSERT` loses rather than
#     interleaving two transcripts into one message list;
#   * the **lease** is `lease_expires_at`, refreshed at every lifecycle
#     event. A worker killed mid-turn stops refreshing, and the next turn
#     steals the lock once it lapses — without that, one crashed container
#     would wedge a conversation permanently;
#   * **ownership** is `run_token`. Every write is conditional on it, so a
#     run whose lease was stolen writes nothing when it comes back. It
#     finds out it was replaced instead of clobbering its replacement.
class ConversationRun < ApplicationRecord
  # How long a lease survives without a refresh. Long enough that a slow
  # model call cannot lapse it (turns run ~60s, ticks fire far more often),
  # short enough that a dead worker does not hold a conversation hostage.
  LEASE_SECONDS = 120

  STATES = %w[running done failed aborted lost_lease].freeze

  # Raised when this run no longer owns the lock — its lease lapsed and
  # someone else took over. The turn must stop writing immediately.
  class LostLease < StandardError; end

  # Raised when the user pressed stop. Distinct from LostLease because the
  # UX differs: one is "you stopped it", the other is "we lost it".
  class Aborted < StandardError; end

  belongs_to :conversation

  validates :state, inclusion: { in: STATES }

  scope :running, -> { where(state: "running") }

  class << self
    # Takes the lock, stealing a lapsed one. Returns nil when a live run
    # already holds it.
    #
    # The steal is a conditional UPDATE rather than delete-then-insert:
    # two workers racing to steal the same lapsed lease both match the
    # WHERE, but only one gets the row back, because the UPDATE takes a
    # row lock and the second re-evaluates against a token that no longer
    # matches.
    def acquire(conversation)
      steal(conversation) || insert_new(conversation)
    end

    private

    # `requires_new` is load-bearing, not ceremony. Postgres aborts the
    # whole transaction on a constraint violation, so catching one raised
    # inside an enclosing transaction would leave that transaction dead
    # and every later statement in it failing. The savepoint scopes the
    # rollback to this insert.
    def insert_new(conversation)
      transaction(requires_new: true) do
        create!(
          conversation:     conversation,
          run_token:        SecureRandom.uuid,
          state:            "running",
          started_at:       Time.current,
          lease_expires_at: LEASE_SECONDS.seconds.from_now
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # The partial unique index did its job: someone else is running.
      nil
    end

    def steal(conversation)
      token = SecureRandom.uuid
      rows  = running.where(conversation_id: conversation.id)
                     .where(lease_expires_at: ...Time.current)
                     .update_all(
                       run_token:        token,
                       started_at:       Time.current,
                       lease_expires_at: LEASE_SECONDS.seconds.from_now,
                       # A stolen run starts fresh: the abort flag belonged
                       # to the run that died, and honouring it here would
                       # kill a turn the user never asked to stop.
                       abort_requested_at: nil,
                       updated_at:       Time.current
                     )
      return nil if rows.zero?

      find_by(run_token: token)
    end
  end

  # Called at every lifecycle event: before each model call, and around
  # each tool. Refreshes the lease and reads the abort flag in one
  # statement, so a stalled turn and a stop button are both caught at the
  # next checkpoint rather than at the end.
  def tick!
    updated = self.class.running
                  .where(run_token: run_token)
                  .update_all(lease_expires_at: LEASE_SECONDS.seconds.from_now, updated_at: Time.current)
    raise LostLease, "run #{id} no longer holds the lock" if updated.zero?

    raise Aborted, "run #{id} was stopped by the user" if abort_requested?

    true
  end

  # Deliberately re-read rather than trusting the loaded attribute: the
  # flag is set by a different request while this one is mid-turn.
  #
  # Compared against `started_at` so a flag left behind by an earlier run
  # cannot abort this one — never erase an abort that belongs to a newer
  # run, and never honour one that belongs to an older.
  def abort_requested?
    requested = self.class.where(id: id).pick(:abort_requested_at)
    requested.present? && requested >= started_at
  end

  # A model call that is part of the turn but not a round of the agent
  # loop — today that is the grounding reviewer. Its tokens and cost are
  # real and belong on the run; its round count is not, because `rounds`
  # answers "how many times did the loop go around", and folding a side
  # call into it would quietly change what the metric means.
  #
  # Unlike `record_round!` this does **not** raise on a lost lease. It
  # runs after the answer already exists, so turning a finished turn into
  # an error to report a billing write is the wrong trade — the round
  # accrual is on the critical path and this is not.
  def record_side_call!(usage, model:)
    self.class
        .where(id: id, run_token: run_token)
        .update_all([
          "input_tokens = input_tokens + ?, output_tokens = output_tokens + ?, " \
          "cache_read_tokens = cache_read_tokens + ?, cache_write_tokens = cache_write_tokens + ?, " \
          "cost_micro_cents = cost_micro_cents + ?, updated_at = ?",
          usage["input_tokens"].to_i, usage["output_tokens"].to_i,
          usage["cache_read_input_tokens"].to_i, usage["cache_creation_input_tokens"].to_i,
          ::Ingestion::UsageCost.micro_cents(usage, model: model), Time.current
        ])
  end

  # Conditional on `run_token`, like `tick!` and `release!` — a run whose
  # lease was stolen must find out it was replaced rather than keep
  # writing tokens and cost onto the row that replaced it. This was the
  # one accrual that wrote unconditionally.
  #
  # **Raises `LostLease` rather than returning false**, the same way
  # `tick!` does on the same condition. A boolean the caller ignores is
  # not "finding out": the loop would drop the round silently and keep
  # calling the model — spending real money on a conversation it no
  # longer owns — until the next `tick!` raised anyway. Raising here ends
  # it a full model call earlier.
  #
  # `rounds` moves in the same statement rather than through
  # `increment!`, so a lost lease cannot leave a run whose round count
  # advanced but whose tokens did not.
  def record_round!(usage, model:)
    micro   = ::Ingestion::UsageCost.micro_cents(usage, model: model)
    updated = self.class
                  .where(id: id, run_token: run_token)
                  .update_all([
                    "rounds = rounds + 1, input_tokens = input_tokens + ?, " \
                    "output_tokens = output_tokens + ?, cache_read_tokens = cache_read_tokens + ?, " \
                    "cache_write_tokens = cache_write_tokens + ?, " \
                    "cost_micro_cents = cost_micro_cents + ?, updated_at = ?",
                    usage["input_tokens"].to_i, usage["output_tokens"].to_i,
                    usage["cache_read_input_tokens"].to_i,
                    usage["cache_creation_input_tokens"].to_i, micro, Time.current
                  ])
    raise_lost_lease!(micro) if updated.zero?

    reload
    true
  end

  # The attribution is dropped; the money is not.
  #
  # `call_model` charges the conversation *before* this runs, and the
  # daily ceiling sums these rows — so a charge that vanished because the
  # lease moved would leave the two ledgers disagreeing and punch a hole
  # in the ceiling. Anthropic billed the call either way.
  #
  # Only the money, though. Rounds and token counts are attribution, and
  # attribution belongs to whoever holds the lease: `steal` rotates the
  # token **in place**, so this is the same row the replacement is now
  # using, and inflating its counters is exactly what the guard exists to
  # prevent. The cost is different in kind — it was spent on this
  # conversation, today, and the aggregate needs it whoever owns the row.
  def raise_lost_lease!(micro)
    if micro.positive?
      self.class.where(id: id).update_all(
        [ "cost_micro_cents = cost_micro_cents + ?, updated_at = ?", micro, Time.current ]
      )
    end

    raise LostLease, "run #{id} no longer holds the lock"
  end

  # Releases the lock. Conditional on the token so a run that already lost
  # its lease cannot mark someone else's run finished.
  def release!(outcome:, state: "done")
    self.class.running
        .where(run_token: run_token)
        .update_all(
          state:       state,
          outcome:     outcome.to_s.truncate(200),
          finished_at: Time.current,
          duration_ms: ((Time.current - started_at) * 1000).round,
          updated_at:  Time.current
        )
  end
end
