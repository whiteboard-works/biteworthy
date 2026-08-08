require "rails_helper"

# The streaming half of the chat. What matters here is that the wire
# format is parseable, that the turn is persisted whatever the stream
# does, and that a bad request is refused *before* the stream opens —
# once headers are out there is no way to send a status code.
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

  # Parses the SSE body back into the payloads the client would see.
  def events
    response.body.split("\n\n").filter_map do |chunk|
      data = chunk.lines.filter_map { |l| l.delete_prefix("data:").strip if l.start_with?("data:") }.join
      JSON.parse(data) if data.present?
    end
  end

  describe "POST /api/v1/conversations/:id/messages" do
    it "streams the turn as server-sent events" do
      script(say("Hello there."))

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "hi" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("text/event-stream")
      expect(events.first["type"]).to eq("open")
      expect(events.last).to eq("type" => "done", "text" => "Hello there.")
      expect(events.filter_map { |e| e["text"] if e["type"] == "text_delta" }.join).to eq("Hello there.")
    end

    it "persists both sides of the turn regardless of the stream" do
      script(say("Hello there."))

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "hi" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(conversation.messages.reload.pluck(:role)).to eq(%w[user assistant])
    end

    it "narrates a tool call" do
      script(call_tool("get_restaurant", { "restaurant" => "ninis" }), say("It's on Main Ave."))

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "tell me about ninis" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(events.map { |e| e["type"] })
        .to include("tool_use", "tool_result")
      expect(events.find { |e| e["type"] == "tool_result" }["ok"]).to be(true)
    end

    # The list needs a label, and the first thing said is the best one
    # available without spending a model call on it.
    it "titles an untitled conversation from the opening message" do
      script(say("Sure."))

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "what can I eat at Ninis?" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(conversation.reload.title).to eq("what can I eat at Ninis?")
    end

    it "rejects an empty message before opening the stream" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "  " }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to be_present
    end

    # Sending a new message while a destructive call waits would leave
    # the tool_use dangling forever.
    it "refuses a new message while a confirmation is parked" do
      conversation.update!(state: "awaiting_confirmation",
                           pending_tool_call: { "results" => [], "queue" => [{ "name" => "delete_review" }] })

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "never mind" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:conflict)
    end

    it "404s another account's conversation" do
      other = create(:conversation, user: create(:user))

      post "/api/v1/conversations/#{other.id}/messages",
           params: { message: "hi" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:not_found)
    end

    it "requires a signed-in caller" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "hi" }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/conversations/:id/confirm" do
    let!(:item)   { create(:item, :published, restaurant: restaurant) }
    let!(:review) { create(:review, user: user, item: item, body: "fine") }

    before do
      script(call_tool("delete_review", { "review_id" => review.id }))
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { message: "delete my review" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
    end

    it "parks the destructive call and says so on the stream" do
      expect(events.last["type"]).to eq("awaiting_confirmation")
      expect(events.last["tool"]["name"]).to eq("delete_review")
      expect(Review.exists?(review.id)).to be(true)
    end

    it "runs the call and finishes the turn once approved" do
      script(say("Deleted."))

      post "/api/v1/conversations/#{conversation.id}/confirm",
           params: { confirm: true }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(events.last).to eq("type" => "done", "text" => "Deleted.")
      expect(Review.exists?(review.id)).to be(false)
      expect(conversation.reload.state).to eq("active")
    end

    it "tells the model no and leaves the record alone when declined" do
      script(say("Okay, left it alone."))

      post "/api/v1/conversations/#{conversation.id}/confirm",
           params: { confirm: false }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(Review.exists?(review.id)).to be(true)
      expect(conversation.reload.state).to eq("active")
    end

    it "409s when nothing is waiting" do
      conversation.reload.update!(state: "active", pending_tool_call: nil)

      post "/api/v1/conversations/#{conversation.id}/confirm",
           params: { confirm: true }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:conflict)
    end

    it "422s an answer that is neither yes nor no" do
      post "/api/v1/conversations/#{conversation.id}/confirm",
           params: { confirm: "maybe" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
