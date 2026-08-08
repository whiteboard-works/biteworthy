# Canned stand-ins for AnthropicClient, shared by the chat loop's unit
# specs and the SSE request specs. Each call pops the next response, so
# a spec reads as "the model said X, then Y".
class ScriptedClient
  attr_reader :requests, :last_usage

  def initialize(*responses)
    @responses  = responses
    @requests   = []
    @last_usage = { "input_tokens" => 100, "output_tokens" => 50 }
  end

  def messages_create(**args)
    @requests << args
    next_response
  end

  def system_blocks(*blocks)
    blocks.flatten.map do |b|
      block = { type: "text", text: b.fetch(:text) }
      block[:cache_control] = { type: "ephemeral" } if b[:cache]
      block
    end
  end

  private

  def next_response
    response = @responses.shift || raise("ScriptedClient ran out of responses after #{@requests.size} calls")
    raise response if response.is_a?(StandardError)

    response
  end
end

# The streaming twin: replays each canned response word by word so the
# loop's narration is driven the way a real stream drives it.
class StreamingScriptedClient < ScriptedClient
  def messages_stream(**args, &on_delta)
    @requests << args
    response = next_response

    Array(response["content"]).each do |block|
      next unless block["type"] == "text"

      block["text"].scan(/\S+\s*/) { |fragment| on_delta&.call(:text, fragment) }
    end
    response
  end
end
