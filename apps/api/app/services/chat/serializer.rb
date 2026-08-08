# frozen_string_literal: true

module Chat
  # Turns stored conversations into what a client renders.
  #
  # Replay and the live stream have to agree, or a page refresh would
  # redraw the turn differently than the user just watched it happen.
  # So the block shapes here mirror the SSE event payloads: text,
  # thinking, tool_use, tool_result.
  #
  # Thinking **signatures are dropped**. They exist so the model can
  # verify its own reasoning on the next request, they are meaningless to
  # a client, and they are the bulkiest thing in the record.
  module Serializer
    RENDERED_BLOCKS = %w[text thinking tool_use tool_result].freeze

    class << self
      def conversation(conversation, messages: false)
        payload = {
          id:         conversation.id,
          title:      conversation.title,
          state:      conversation.state,
          pending:    pending(conversation),
          created_at: conversation.created_at.iso8601,
          updated_at: conversation.updated_at.iso8601
        }
        messages ? payload.merge(messages: conversation.messages.map { |m| message(m) }) : payload
      end

      def message(message)
        {
          id:       message.id,
          role:     message.role,
          position: message.position,
          blocks:   blocks(message)
        }
      end

      private

      # The tool call the loop parked on, so a reloaded page can redraw
      # the confirmation prompt instead of stranding the conversation.
      def pending(conversation)
        return nil unless conversation.awaiting_confirmation?

        call = Array(conversation.pending_tool_call&.dig("queue")).first
        return nil if call.nil?

        { name: call["name"], input: call["input"] }
      end

      def blocks(message)
        Array(message.content).filter_map do |raw|
          block = raw.respond_to?(:deep_stringify_keys) ? raw.deep_stringify_keys : {}
          next unless RENDERED_BLOCKS.include?(block["type"])

          render(block)
        end
      end

      def render(block)
        case block["type"]
        when "text"     then { type: "text", text: block["text"] }
        when "thinking" then { type: "thinking", text: block["thinking"] }
        when "tool_use" then { type: "tool_use", id: block["id"], name: block["name"], input: block["input"] }
        else                 tool_result(block)
        end
      end

      def tool_result(block)
        {
          type:        "tool_result",
          tool_use_id: block["tool_use_id"],
          ok:          block["is_error"] != true,
          text:        Array(block["content"]).filter_map { |c| c["text"] }.join("\n").presence
        }
      end
    end
  end
end
