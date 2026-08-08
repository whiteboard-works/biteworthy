# frozen_string_literal: true

class AnthropicClient
  # Reassembles Anthropic's SSE stream into the same Hash a non-streaming
  # `/v1/messages` call returns, yielding deltas as they arrive.
  #
  # The chat needs both halves: the caller wants text on screen while the
  # model is still writing, and `Chat::AgentLoop` needs the finished
  # message to append to the transcript and to read `stop_reason` from.
  # Assembling here means the loop's logic is identical streaming or not.
  #
  # Two details are load-bearing:
  #
  #   * **Thinking signatures are copied, never rebuilt.** A thinking
  #     block replayed without its exact signature is rejected on the
  #     next request, which would wedge the conversation.
  #   * **Tool input arrives as partial JSON fragments** that are only
  #     valid once concatenated — parsing before `content_block_stop`
  #     fails on every block but the last. This applies to server-side
  #     tools (tool search) exactly as it does to the model's own calls.
  class Stream
    # A stream that ends without `message_stop` — a dropped connection or
    # a truncated proxy response. The turn is unusable either way.
    class IncompleteError < StandardError; end

    attr_reader :usage

    def initialize(&on_delta)
      @on_delta = on_delta
      reset
    end

    # Feeds a raw chunk of the HTTP body. Chunks split anywhere, including
    # mid-event, so the tail is buffered until a blank line completes it.
    def <<(chunk)
      @buffer << chunk
      while (index = @buffer.index("\n\n"))
        event = @buffer.slice!(0, index + 2)
        handle(data_payload(event))
      end
      self
    end

    def complete? = @complete

    def message
      raise IncompleteError, "stream ended before message_stop" unless @complete

      @message.merge("content" => @blocks.map { |block| finalize(block) }, "usage" => @usage)
    end

    private

    def reset
      @buffer   = +""
      @blocks   = []
      @message  = {}
      @usage    = {}
      @complete = false
    end

    # An SSE event is `event:` and `data:` lines; the `data:` JSON carries
    # its own `type`, so the `event:` line is redundant and ignored.
    def data_payload(event)
      json = event.lines.filter_map { |line| line.delete_prefix("data:").strip if line.start_with?("data:") }.join
      return nil if json.empty?

      JSON.parse(json)
    rescue JSON::ParserError
      nil
    end

    def handle(payload)
      case payload&.fetch("type", nil)
      when "message_start"        then start_message(payload["message"])
      when "content_block_start"  then @blocks[payload["index"]] = payload["content_block"].dup
      when "content_block_delta"  then apply_delta(payload["index"], payload["delta"])
      when "message_delta"        then apply_message_delta(payload)
      when "message_stop"         then @complete = true
      when "error"                then raise_stream_error(payload["error"])
      end
    end

    # A retry replays the stream from the top; anything accumulated from
    # the abandoned attempt has to go or the message doubles up.
    def start_message(message)
      buffered = @buffer
      reset
      @buffer  = buffered
      @message = (message || {}).except("content", "usage")
      @usage   = (message || {}).fetch("usage", {}).dup
    end

    def apply_delta(index, delta)
      block = @blocks[index]
      return if block.nil?

      case delta["type"]
      when "text_delta"
        block["text"] = "#{block['text']}#{delta['text']}"
        emit(:text, delta["text"])
      when "thinking_delta"
        block["thinking"] = "#{block['thinking']}#{delta['thinking']}"
        emit(:thinking, delta["thinking"])
      when "signature_delta"
        block["signature"] = "#{block['signature']}#{delta['signature']}"
      when "input_json_delta"
        # Held as a string until content_block_stop — a fragment is not
        # parseable on its own.
        block["partial_json"] = "#{block['partial_json']}#{delta['partial_json']}"
      end
    end

    # Output tokens only land here, at the end; the input and cache counts
    # came with message_start.
    def apply_message_delta(payload)
      @message.merge!(payload["delta"] || {})
      @usage.merge!(payload["usage"] || {})
    end

    # Keyed on the accumulator, not on a list of block types — the list
    # grows. `tool_use` was the only one until tool search shipped, and a
    # `server_tool_use` left unfinalized carries an empty `input` plus the
    # leftover scratch field, which the API rejects the moment the
    # transcript replays. Anything that streams its input as JSON
    # fragments gets the same treatment from here on.
    def finalize(block)
      return block unless block.key?("partial_json")

      partial = block.delete("partial_json")
      block.merge("input" => partial.present? ? JSON.parse(partial) : (block["input"] || {}))
    rescue JSON::ParserError
      # Better a tool call with empty arguments — which the tool rejects
      # with a message the model can act on — than a dead turn.
      block.merge("input" => {})
    end

    def emit(kind, text)
      @on_delta&.call(kind, text)
    end

    def raise_stream_error(error)
      raise ApiError.new(
        status: 200,
        body: error,
        message: "Anthropic stream error: #{error&.fetch('type', 'unknown')} #{error&.fetch('message', nil)}"
      )
    end
  end
end
