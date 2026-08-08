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
    messages.reload.map { |m| { role: m.role, content: m.content } }
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

  # Deliberately not `messages.maximum` — on a loaded association that
  # computes from the in-memory cache, which the loop has already made
  # stale by appending.
  def next_position
    Message.where(conversation_id: id).maximum(:position).to_i + 1
  end
end
