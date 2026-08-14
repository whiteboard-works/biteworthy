require "rails_helper"

# The chat's HTTP surface, now that a turn runs in a job.
#
# The contract these pin: the request only records what was asked and
# hands off, the work happens whether or not anyone is still connected,
# and the narration is a replayable record rather than bytes that vanish
# with the socket.
RSpec.describe "Api::V1::ConversationTurns", type: :request do
  let(:user)         { create(:user) }
  let(:headers)      { auth_headers_for(user) }
  let(:conversation) { create(:conversation, user: user, title: nil) }
  let!(:city)        { create(:city, slug: "durango", name: "Durango") }
  let!(:restaurant)  { create(:restaurant, :published, city: city, name: "Ninis Taqueria", slug: "ninis") }

  def say(text)
    { "stop_reason" => "end_turn", "content" => [{ "type" => "text", "text" => text }] }
  end

  def call_tool(name, input = {}, id: "toolu_1")
    { "stop_reason" => "tool_use",
      "content" => [{ "type" => "tool_use", "id" => id, "name" => name, "input" => input }] }
  end

  def script(*responses)
    allow(AnthropicClient).to receive(:new).and_return(StreamingScriptedClient.new(*responses))
  end

  def send_message(text, id: conversation.id, mode: nil)
    post "/api/v1/conversations/#{id}/messages",
         params: { message: text, mode: mode }.compact.to_json,
         headers: headers.merge("Content-Type" => "application/json")
  end

  # The turn is a job now, so a test drives it explicitly rather than
  # getting it as a side effect of the request.
  def work
    Chat::CompletionJob.perform_now(conversation.id)
  end

  # The narration as a client would read it back.
  def narration
    conversation.events.in_order.map(&:payload)
  end

  describe "POST /api/v1/conversations/:id/messages" do
    # The whole point of the phase: the request does not wait for a model.
    it "records the turn, hands off, and answers immediately" do
      send_message("hi")

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["queued"]).to be(true)
      expect(conversation.reload.pending_turns.length).to eq(1)
      expect(Chat::CompletionJob).to have_been_enqueued.with(conversation.id)
    end

    # A message appended to the transcript at request time would land in
    # the middle of a running turn's message list, and that turn would
    # then answer it. The queue is the serialization point.
    it "does not touch the transcript until the job holds the lock" do
      send_message("hi")

      expect(conversation.messages.reload).to be_empty
    end

    it "runs the turn and persists both sides when the job picks it up" do
      script(say("Hello there."))
      send_message("hi")

      work

      expect(conversation.messages.reload.pluck(:role)).to eq(%w[user assistant])
      expect(narration.last).to include("type" => "done", "text" => "Hello there.")
    end

    it "writes the tool call and its result into the narration" do
      script(call_tool("get_restaurant", { "restaurant" => "ninis" }), say("It's on Main Ave."))
      send_message("tell me about ninis")

      work

      types = narration.map { |e| e["type"] }
      expect(types).to include("tool_use", "tool_result")
      expect(narration.find { |e| e["type"] == "tool_result" }["ok"]).to be(true)
    end

    # A row per token would be tens of thousands of inserts for one
    # answer, and a table nobody could read.
    it "coalesces text deltas instead of writing a row per token" do
      script(say("Hello there."))
      send_message("hi")

      work

      deltas = narration.select { |e| e["type"] == "text_delta" }
      expect(deltas.map { |e| e["text"] }.join).to eq("Hello there.")
      expect(deltas.length).to be < "Hello there.".length
    end

    # Rapid-fire messages serialize behind the lock. None are dropped, and
    # none interleave.
    it "queues a second message behind the first rather than racing it" do
      script(say("first"), say("second"))
      send_message("one")
      send_message("two")

      work

      expect(conversation.reload.pending_turns).to be_empty
      expect(conversation.messages.reload.pluck(:role)).to eq(%w[user assistant user assistant])
    end

    # Stamped at enqueue rather than read by the job, so a mode picked
    # while this turn is in flight belongs to the next one.
    describe "the turn's mode" do
      it "rides in the queued payload" do
        send_message("hi", mode: "planning")

        expect(conversation.reload.pending_turns.first["mode"]).to eq("planning")
      end

      # A client may switch and send in one request, so the picker cannot
      # lose a race with the message it was changed for.
      it "is persisted on the conversation too, so a reload keeps it" do
        send_message("hi", mode: "auto")

        expect(conversation.reload.chat_mode).to eq("auto")
      end

      it "defaults to whatever the conversation already had" do
        conversation.update!(chat_mode: "accept_edits")

        send_message("hi")

        expect(conversation.reload.pending_turns.first["mode"]).to eq("accept_edits")
      end

      # Refused rather than quietly read as `manual`: someone who asked
      # for `planning` and silently got `manual` has writes running they
      # thought were off.
      it "refuses an unknown mode without queuing the message" do
        send_message("hi", mode: "yolo")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(conversation.reload.pending_turns).to be_empty
      end
    end

    # The controller deliberately writes NO title. It used to stamp the
    # opening message in before enqueuing, which left
    # `AgentLoop#name_conversation` looking at a title that was already
    # present — so `Chat::Titler` never ran, and the sidebar showed the
    # raw question forever. Both halves had specs; neither crossed this
    # boundary, so nothing failed. These two do cross it.
    it "leaves the title for the turn to write, not the request" do
      send_message("what can I eat at Ninis?")

      expect(response).to have_http_status(:accepted)
      expect(conversation.reload.title).to be_nil
    end

    it "names the conversation from the model once the turn lands" do
      script(say("Ninis has three gluten-free dishes."))
      titled("Gluten-free options at Ninis")

      send_message("what can I eat at Ninis?")
      work

      expect(conversation.reload.title).to eq("Gluten-free options at Ninis")
    end

    it "rejects an empty message without queuing anything" do
      send_message("  ")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.reload.pending_turns).to be_empty
    end

    # Sending a new message while a destructive call waits would leave the
    # tool_use dangling forever.
    it "refuses a new message while a confirmation is parked" do
      conversation.update!(state: "awaiting_confirmation",
                           pending_tool_call: { "results" => [], "queue" => [{ "name" => "delete_review" }] })

      send_message("never mind")

      expect(response).to have_http_status(:conflict)
    end

    it "404s another account's conversation" do
      send_message("hi", id: create(:conversation, user: create(:user)).id)

      expect(response).to have_http_status(:not_found)
    end

    it "requires a signed-in caller" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "hi" }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/conversations/:id/stream" do
    before do
      script(say("Hello there."))
      send_message("hi")
      work
    end

    # Parses the SSE body back into what a client would see.
    def streamed
      response.body.split("\n\n").filter_map do |chunk|
        data = chunk.lines.filter_map { |l| l.delete_prefix("data:").strip if l.start_with?("data:") }.join
        JSON.parse(data) if data.present?
      end
    end

    # The reconnect story, and the reason events are rows: a client that
    # dropped mid-turn resumes the narration from where it stopped instead
    # of waiting blind for the turn to end.
    it "replays everything after the position the client last saw" do
      get "/api/v1/conversations/#{conversation.id}/stream",
          headers: headers.merge("Last-Event-ID" => "0")

      expect(response.headers["Content-Type"]).to include("text/event-stream")
      expect(streamed.last).to include("type" => "done", "text" => "Hello there.")
    end

    it "carries the position on each event so a reader can resume" do
      get "/api/v1/conversations/#{conversation.id}/stream",
          headers: headers.merge("Last-Event-ID" => "0")

      expect(response.body).to include("id: 1\n")
    end

    it "sends nothing already seen, and closes instead of holding the thread" do
      last  = conversation.events.maximum(:position)
      began = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      get "/api/v1/conversations/#{conversation.id}/stream",
          headers: headers.merge("Last-Event-ID" => last.to_s)

      expect(streamed).to be_empty

      # The timing is the point, not incidental. This reader is caught up
      # on a finished turn, so there is no terminal event left to end the
      # stream on: without an idle exit the request sits on a Puma thread
      # for the full STREAM_SECONDS, which costs a thread in production
      # and five silent minutes of CI here.
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began
      expect(elapsed).to be < 10
    end

    it "404s another account's conversation" do
      get "/api/v1/conversations/#{create(:conversation, user: create(:user)).id}/stream", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/conversations/:id/confirm" do
    let!(:item)   { create(:item, :published, restaurant: restaurant) }
    let!(:review) { create(:review, user: user, item: item, body: "fine") }

    before do
      script(call_tool("delete_review", { "review_id" => review.id }))
      send_message("delete my review")
      work
    end

    def parked_fingerprint
      conversation.reload.pending_tool_call&.dig("pending", "fingerprint")
    end

    def answer(confirm:, fingerprint: parked_fingerprint)
      post "/api/v1/conversations/#{conversation.id}/confirm",
           params: { confirm: confirm, fingerprint: fingerprint }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
    end

    it "parks the destructive call and says so in the narration" do
      expect(narration.last["type"]).to eq("awaiting_confirmation")
      expect(narration.last["tool"]["name"]).to eq("delete_review")
      expect(narration.last["tool"]["fingerprint"]).to be_present
      expect(Review.exists?(review.id)).to be(true)
    end

    it "runs the call and finishes the turn once approved" do
      script(say("Deleted."))
      answer(confirm: true)

      work

      expect(Review.exists?(review.id)).to be(false)
      expect(conversation.reload.state).to eq("active")
      expect(narration.last).to include("type" => "done", "text" => "Deleted.")
    end

    it "tells the model no and leaves the record alone when declined" do
      script(say("Okay, left it alone."))
      answer(confirm: false)

      work

      expect(Review.exists?(review.id)).to be(true)
      expect(conversation.reload.state).to eq("active")
    end

    it "409s when nothing is waiting" do
      conversation.reload.update!(state: "active", pending_tool_call: nil)

      answer(confirm: true)

      expect(response).to have_http_status(:conflict)
    end

    # The gate is only as good as what it is bound to: a tab left open on
    # an earlier prompt must not be able to approve whatever is parked now.
    it "refuses an answer that does not match the parked call" do
      script(say("Deleted."))
      answer(confirm: true, fingerprint: "stale-token")

      work

      expect(Review.exists?(review.id)).to be(true)
      expect(conversation.reload.state).to eq("awaiting_confirmation")
      expect(narration.last["type"]).to eq("error")
    end

    it "422s an answer that is neither yes nor no" do
      post "/api/v1/conversations/#{conversation.id}/confirm",
           params: { confirm: "maybe" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # A menu scan legitimately outlives one connection. Without a cursor the
  # client cannot tell "the turn ended" from "your connection did", and it
  # would redraw a half-finished turn as final.
  describe "a turn that outlives one connection" do
    before do
      script(say("Hello there."))
      send_message("hi")
      work
    end

    it "hands back a resume cursor instead of just closing" do
      stub_const("Api::V1::ConversationTurnsController::STREAM_SECONDS", 0)
      # Still queued, so the relay knows the turn is not over.
      conversation.enqueue_turn!("kind" => "message", "text" => "and another")

      get "/api/v1/conversations/#{conversation.id}/stream",
          headers: headers.merge("Last-Event-ID" => "0")

      last = response.body.split("\n\n").filter_map do |chunk|
        data = chunk.lines.filter_map { |l| l.delete_prefix("data:").strip if l.start_with?("data:") }.join
        JSON.parse(data) if data.present?
      end.last

      expect(last["type"]).to eq("reconnect")
      expect(last["after"]).to be_present
    end

    # A finished conversation must close cleanly — a spurious reconnect
    # would have the client reopen a stream forever.
    it "does not ask for a reconnect once the turn is done" do
      get "/api/v1/conversations/#{conversation.id}/stream",
          headers: headers.merge("Last-Event-ID" => "0")

      expect(response.body).not_to include('"type":"reconnect"')
    end
  end
end

