class Message < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :conversation

  validates :role, inclusion: { in: ROLES }
  validates :position, presence: true

  # Tool results are `user`-role messages carrying tool_result blocks —
  # that is the Messages API shape, not a modelling choice. This tells
  # them apart from something a person typed.
  def tool_result?
    role == "user" && blocks.any? { |block| block["type"] == "tool_result" }
  end

  def tool_uses
    blocks.select { |block| block["type"] == "tool_use" }
  end

  # The visible prose, with thinking and tool plumbing dropped.
  def text
    blocks.filter_map { |block| block["text"] if block["type"] == "text" }.join("\n").presence
  end

  private

  # jsonb comes back string-keyed after a reload but symbol-keyed before
  # one. Normalizing here keeps every reader from having to care.
  def blocks
    Array(content).map { |block| block.respond_to?(:deep_stringify_keys) ? block.deep_stringify_keys : block }
  end
end
