class Conversation < ApplicationRecord
  # `awaiting_confirmation` is the human gate. The loop stops there
  # rather than calling a tool annotated destructive, and the call it
  # wanted to make waits in `pending_tool_call` until the user answers.
  STATES = %w[active awaiting_confirmation failed].freeze

  belongs_to :user
  has_many :messages, -> { order(:position) }, dependent: :destroy, inverse_of: :conversation

  validates :state, inclusion: { in: STATES }

  scope :newest_first, -> { order(updated_at: :desc) }

  def awaiting_confirmation? = state == "awaiting_confirmation"

  # The Anthropic `messages` array for the next request: every stored
  # turn, verbatim. Tool-use, tool-result, and thinking blocks all have
  # to replay exactly — a thinking block's signature is rejected if it
  # was rebuilt rather than echoed.
  def transcript
    stored = messages.reload.to_a
    stored.map { |m| { role: m.role, content: m.content } } + repair_for(stored.last)
  end

  # Locked for the whole insert, not just the position read: two turns
  # racing would otherwise pick the same position, collide on the unique
  # index, and lose one side's message.
  def append!(role:, content:)
    with_lock do
      messages.create!(role: role, content: content, position: next_position)
    end
  end

  def record_usage!(usage, model:)
    increment!(:api_cost_cents, ::Ingestion::UsageCost.cents(usage, model: model))
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
