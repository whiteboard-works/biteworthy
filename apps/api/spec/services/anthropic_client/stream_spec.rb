require "rails_helper"

# The stream assembler is what lets the chat show words as they arrive
# while still handing the loop a complete message. If it reassembles
# wrong the damage is invisible until a later turn: a thinking block
# missing its signature, or a tool called with the wrong arguments.
RSpec.describe AnthropicClient::Stream do
  def event(type, payload)
    "event: #{type}\ndata: #{payload.merge(type: type).to_json}\n\n"
  end

  def start(usage: { "input_tokens" => 10 })
    event("message_start", { message: { id: "msg_1", role: "assistant", model: "claude-opus-5", usage: usage } })
  end

  def stop(stop_reason: "end_turn", usage: { "output_tokens" => 7 })
    event("message_delta", { delta: { stop_reason: stop_reason }, usage: usage }) +
      event("message_stop", {})
  end

  def feed(stream, body)
    body.each_char { |c| stream << c }
    stream
  end

  it "assembles text the same shape a non-streaming call returns" do
    stream = described_class.new
    stream << start
    stream << event("content_block_start", { index: 0, content_block: { type: "text", text: "" } })
    stream << event("content_block_delta", { index: 0, delta: { type: "text_delta", text: "Hello " } })
    stream << event("content_block_delta", { index: 0, delta: { type: "text_delta", text: "world" } })
    stream << event("content_block_stop", { index: 0 })
    stream << stop

    expect(stream.message["content"]).to eq([{ "type" => "text", "text" => "Hello world" }])
    expect(stream.message["stop_reason"]).to eq("end_turn")
    expect(stream.message["id"]).to eq("msg_1")
  end

  # Chunk boundaries follow the network, not the protocol — an event can
  # be split anywhere, including between the `d` and the `ata:`.
  it "tolerates a body chopped one character at a time" do
    body = start +
           event("content_block_start", { index: 0, content_block: { type: "text", text: "" } }) +
           event("content_block_delta", { index: 0, delta: { type: "text_delta", text: "split fine" } }) +
           stop

    expect(feed(described_class.new, body).message["content"].first["text"]).to eq("split fine")
  end

  it "yields text and thinking fragments as they arrive" do
    seen   = []
    stream = described_class.new { |kind, text| seen << [kind, text] }
    stream << start
    stream << event("content_block_start", { index: 0, content_block: { type: "thinking", thinking: "" } })
    stream << event("content_block_delta", { index: 0, delta: { type: "thinking_delta", thinking: "hmm" } })
    stream << event("content_block_start", { index: 1, content_block: { type: "text", text: "" } })
    stream << event("content_block_delta", { index: 1, delta: { type: "text_delta", text: "hi" } })
    stream << stop

    expect(seen).to eq([[:thinking, "hmm"], [:text, "hi"]])
  end

  # A thinking block replayed without its exact signature is rejected on
  # the next request, which kills the conversation rather than one turn.
  it "carries the thinking signature through verbatim" do
    stream = described_class.new
    stream << start
    stream << event("content_block_start", { index: 0, content_block: { type: "thinking", thinking: "" } })
    stream << event("content_block_delta", { index: 0, delta: { type: "thinking_delta", thinking: "reasoning" } })
    stream << event("content_block_delta", { index: 0, delta: { type: "signature_delta", signature: "abc" } })
    stream << event("content_block_delta", { index: 0, delta: { type: "signature_delta", signature: "123" } })
    stream << stop

    expect(stream.message["content"].first).to eq(
      "type" => "thinking", "thinking" => "reasoning", "signature" => "abc123"
    )
  end

  # Each fragment is invalid JSON on its own; only the concatenation parses.
  it "joins tool_use input fragments before parsing them" do
    stream = described_class.new
    stream << start
    stream << event("content_block_start",
                    { index: 0, content_block: { type: "tool_use", id: "toolu_1", name: "get_menu", input: {} } })
    stream << event("content_block_delta", { index: 0, delta: { type: "input_json_delta", partial_json: '{"resta' } })
    stream << event("content_block_delta",
                    { index: 0, delta: { type: "input_json_delta", partial_json: 'urant":"ninis"}' } })
    stream << event("content_block_stop", { index: 0 })
    stream << stop(stop_reason: "tool_use")

    expect(stream.message["content"].first).to eq(
      "type" => "tool_use", "id" => "toolu_1", "name" => "get_menu", "input" => { "restaurant" => "ninis" }
    )
  end

  # An empty argument hash comes back as a tool error the model can read
  # and correct; a raised parse error would end the turn instead.
  it "falls back to empty arguments when the fragments do not parse" do
    stream = described_class.new
    stream << start
    stream << event("content_block_start",
                    { index: 0, content_block: { type: "tool_use", id: "toolu_1", name: "get_menu", input: {} } })
    stream << event("content_block_delta", { index: 0, delta: { type: "input_json_delta", partial_json: '{"broken' } })
    stream << stop(stop_reason: "tool_use")

    expect(stream.message["content"].first["input"]).to eq({})
  end

  it "merges the input usage from the start with the output usage from the end" do
    stream = described_class.new
    stream << start(usage: { "input_tokens" => 12, "cache_read_input_tokens" => 900 })
    stream << stop(usage: { "output_tokens" => 34 })

    expect(stream.usage).to eq(
      "input_tokens" => 12, "cache_read_input_tokens" => 900, "output_tokens" => 34
    )
  end

  # A retried request replays from message_start. Without a reset the two
  # attempts would concatenate into one doubled answer.
  it "discards a partial attempt when a second message_start arrives" do
    stream = described_class.new
    stream << start
    stream << event("content_block_start", { index: 0, content_block: { type: "text", text: "" } })
    stream << event("content_block_delta", { index: 0, delta: { type: "text_delta", text: "first try" } })
    stream << start
    stream << event("content_block_start", { index: 0, content_block: { type: "text", text: "" } })
    stream << event("content_block_delta", { index: 0, delta: { type: "text_delta", text: "second try" } })
    stream << stop

    expect(stream.message["content"]).to eq([{ "type" => "text", "text" => "second try" }])
  end

  it "raises on a mid-stream error event" do
    stream = described_class.new
    stream << start

    expect { stream << event("error", { error: { type: "overloaded_error", message: "Overloaded" } }) }
      .to raise_error(AnthropicClient::ApiError, /overloaded_error/)
  end

  # Half a turn is worse than none: the loop would append a truncated
  # assistant message and carry it forever.
  it "refuses to hand back a message that never reached message_stop" do
    stream = described_class.new
    stream << start

    expect(stream).not_to be_complete
    expect { stream.message }.to raise_error(described_class::IncompleteError)
  end

  # Server-side tools stream their input exactly like a client tool does,
  # and until tool search shipped nothing here produced one. An
  # unfinalized server_tool_use carries an empty `input` plus the leftover
  # scratch field, and the API rejects the whole conversation the moment
  # that block replays — so the turn AFTER it dies, not the turn itself.
  # Non-streaming was unaffected, which is exactly why the suite missed it.
  it "finalizes a server tool's streamed input, not just a client tool's" do
    stream = described_class.new
    stream << event("message_start", { message: { id: "msg_1", role: "assistant", content: [], usage: {} } })
    stream << event("content_block_start",
                    { index: 0,
                      content_block: { type: "server_tool_use", id: "srvtoolu_1",
                                       name: "tool_search_tool_regex", input: {} } })
    stream << event("content_block_delta",
                    { index: 0, delta: { type: "input_json_delta", partial_json: '{"pattern":' } })
    stream << event("content_block_delta",
                    { index: 0, delta: { type: "input_json_delta", partial_json: '"list_saved"}' } })
    stream << event("content_block_stop", { index: 0 })
    stream << stop(stop_reason: "tool_use")

    block = stream.message["content"].first
    expect(block["input"]).to eq({ "pattern" => "list_saved" })
    expect(block).not_to have_key("partial_json")
  end

  # The finalizer keys on the accumulator, so it must not invent one for a
  # block that never streamed input.
  it "leaves a block that streamed no input untouched" do
    stream = described_class.new
    stream << event("message_start", { message: { id: "msg_1", role: "assistant", content: [], usage: {} } })
    stream << event("content_block_start", { index: 0, content_block: { type: "text", text: "" } })
    stream << event("content_block_delta", { index: 0, delta: { type: "text_delta", text: "hi" } })
    stream << stop(stop_reason: "end_turn")

    expect(stream.message["content"].first).to eq({ "type" => "text", "text" => "hi" })
  end
end

