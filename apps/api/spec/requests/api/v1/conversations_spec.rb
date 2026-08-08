require "rails_helper"

RSpec.describe "Api::V1::Conversations", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/conversations" do
    it "lists the caller's conversations, newest first" do
      old = create(:conversation, user: user, title: "older", updated_at: 2.days.ago)
      recent = create(:conversation, user: user, title: "newer", updated_at: 1.minute.ago)

      get "/api/v1/conversations", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["conversations"].map { |c| c["id"] }).to eq([recent.id, old.id])
    end

    # A transcript is personal. Nobody else's shows up, by id or in a list.
    it "never shows another account's conversations" do
      create(:conversation, user: create(:user), title: "someone else's")

      get "/api/v1/conversations", headers: headers

      expect(response.parsed_body["conversations"]).to be_empty
    end

    it "requires a signed-in caller" do
      get "/api/v1/conversations"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/conversations" do
    it "opens an empty conversation" do
      post "/api/v1/conversations", headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("state" => "active", "messages" => [])
      expect(user.conversations.count).to eq(1)
    end
  end

  describe "GET /api/v1/conversations/:id" do
    let(:conversation) { create(:conversation, user: user) }

    # The reconnect story: a dropped stream costs nothing because the
    # turn was persisted as it ran.
    it "replays the transcript in the shape the live stream used" do
      conversation.append!(role: "user", content: [{ type: "text", text: "what's good here?" }])
      conversation.append!(role: "assistant", content: [
                             { type: "thinking", thinking: "checking", signature: "sig" },
                             { type: "tool_use", id: "toolu_1", name: "get_menu", input: { "restaurant" => "ninis" } }
                           ])
      conversation.append!(role: "user", content: [
                             { type: "tool_result", tool_use_id: "toolu_1", is_error: false,
                               content: [{ type: "text", text: "12 dishes" }] }
                           ])

      get "/api/v1/conversations/#{conversation.id}", headers: headers

      blocks = response.parsed_body["messages"].flat_map { |m| m["blocks"] }
      expect(blocks.map { |b| b["type"] }).to eq(%w[text thinking tool_use tool_result])
      expect(blocks[2]).to include("name" => "get_menu", "input" => { "restaurant" => "ninis" })
      expect(blocks[3]).to include("ok" => true, "text" => "12 dishes")
    end

    # They are only meaningful to the model and they are the bulkiest
    # thing in the record.
    it "leaves thinking signatures out of the client payload" do
      conversation.append!(role: "assistant",
                           content: [{ type: "thinking", thinking: "reasoning", signature: "secret" }])

      get "/api/v1/conversations/#{conversation.id}", headers: headers

      expect(response.body).not_to include("secret")
    end

    # A reload has to be able to redraw the same sentence and answer it —
    # which means the prompt and the binding token replay too, not just the
    # tool name.
    it "redraws a parked confirmation so a reload is not a dead end" do
      conversation.update!(
        state: "awaiting_confirmation",
        pending_tool_call: {
          "results" => [],
          "queue"   => [{ "name" => "delete_review", "input" => { "review_id" => "abc" } }],
          "pending" => { "name" => "delete_review", "input" => { "review_id" => "abc" },
                         "prompt" => "Delete this review?", "fingerprint" => "abc123" }
        }
      )

      get "/api/v1/conversations/#{conversation.id}", headers: headers

      expect(response.parsed_body["pending"]).to eq(
        "name" => "delete_review", "input" => { "review_id" => "abc" },
        "prompt" => "Delete this review?", "fingerprint" => "abc123"
      )
    end

    it "404s another account's conversation" do
      other = create(:conversation, user: create(:user))

      get "/api/v1/conversations/#{other.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/conversations/:id" do
    it "removes the conversation and its messages" do
      conversation = create(:conversation, user: user)
      conversation.append!(role: "user", content: [{ type: "text", text: "hi" }])

      delete "/api/v1/conversations/#{conversation.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(Conversation.exists?(conversation.id)).to be(false)
      expect(Message.where(conversation_id: conversation.id)).to be_empty
    end
  end

  # The stop button. It has to be a separate request from the turn it
  # stops, because the streaming one is busy for the length of the turn —
  # which is exactly the window the user wants to interrupt.
  describe "DELETE /api/v1/conversations/:id/run" do
    let(:conversation) { create(:conversation, user: user) }

    it "raises the flag the running turn reads at its next checkpoint" do
      run = ConversationRun.acquire(conversation)

      delete "/api/v1/conversations/#{conversation.id}/run", headers: headers

      expect(response).to have_http_status(:accepted)
      expect(run.reload.abort_requested_at).to be_present
    end

    it "409s when nothing is running" do
      delete "/api/v1/conversations/#{conversation.id}/run", headers: headers

      expect(response).to have_http_status(:conflict)
    end

    it "404s another account's conversation" do
      other = create(:conversation, user: create(:user))
      ConversationRun.acquire(other)

      delete "/api/v1/conversations/#{other.id}/run", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end

