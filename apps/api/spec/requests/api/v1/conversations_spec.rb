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

    # The historical behaviour, and the strictest of the four that still
    # lets a turn write anything. Nobody opts into a gate.
    it "starts in manual" do
      post "/api/v1/conversations", headers: headers

      expect(response.parsed_body["mode"]).to eq("manual")
    end
  end

  describe "PATCH /api/v1/conversations/:id" do
    let(:conversation) { create(:conversation, user: user) }

    it "switches the mode without sending anything" do
      patch "/api/v1/conversations/#{conversation.id}", params: { mode: "planning" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["mode"]).to eq("planning")
      expect(conversation.reload.chat_mode).to eq("planning")
    end

    # Refused rather than quietly read as `manual`. Falling back is safe
    # in one direction only: someone who asked for `auto` and got
    # `manual` is asked a question they did not expect, but someone who
    # asked for `planning` and got `manual` has writes running they
    # thought were off.
    it "refuses a mode that does not exist" do
      patch "/api/v1/conversations/#{conversation.id}", params: { mode: "yolo" }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.reload.chat_mode).to eq("manual")
    end

    it "cannot reach another account's conversation" do
      other = create(:conversation, user: create(:user))

      patch "/api/v1/conversations/#{other.id}", params: { mode: "auto" }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(other.reload.chat_mode).to eq("manual")
    end
  end

  # `can_undo` answers "did a write run since you last spoke", which the
  # client turns into a one-click reversal. It rides with the messages
  # rather than being sent unconditionally: the sidebar lists every
  # conversation, and answering it there would load every message of
  # every one.
  describe "the undo affordance" do
    let(:conversation) { create(:conversation, user: user) }

    def a_turn_calling(name)
      conversation.append!(role: "user", content: [{ type: "text", text: "do it" }])
      conversation.append!(role: "assistant",
                           content: [{ type: "tool_use", id: "t1", name: name, input: {} }])
    end

    it "offers undo after a write" do
      a_turn_calling("update_avoid_lists")

      get "/api/v1/conversations/#{conversation.id}", headers: headers

      expect(response.parsed_body["can_undo"]).to be(true)
    end

    it "does not offer it after a read" do
      a_turn_calling("get_menu")

      get "/api/v1/conversations/#{conversation.id}", headers: headers

      expect(response.parsed_body["can_undo"]).to be(false)
    end

    # The sidebar has no undo button, and paying a message load per row
    # to tell it so is the kind of thing that is invisible until the
    # list is long.
    it "costs the index nothing" do
      3.times { create(:conversation, user: user) }
      a_turn_calling("update_avoid_lists")

      loaded = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        loaded += 1 if payload[:sql].include?('FROM "messages"')
      end
      get "/api/v1/conversations", headers: headers
      ActiveSupport::Notifications.unsubscribe(sub)

      expect(response.parsed_body["conversations"].first).not_to have_key("can_undo")
      expect(loaded).to eq(0)
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

  # Spend and cache accounting is for whoever operates the tools. It is
  # the one part of this payload that is not about the conversation, and
  # a diner has no use for it.
  describe "usage detail" do
    let(:conversation) { create(:conversation, user: user, spent_cents: 12) }

    it "is withheld from an ordinary caller" do
      get "/api/v1/conversations/#{conversation.id}", headers: headers

      expect(response.parsed_body).not_to have_key("usage")
    end

    it "reports the last run's token split to an admin" do
      admin = create(:user, is_admin: true)
      convo = create(:conversation, user: admin, spent_cents: 34)
      run   = ConversationRun.acquire(convo)
      run.record_round!({ "input_tokens" => 10, "output_tokens" => 5,
                          "cache_read_input_tokens" => 7_550,
                          "cache_creation_input_tokens" => 1_200 },
                        model: Chat::AgentLoop::MODEL)
      run.release!(outcome: "done")

      get "/api/v1/conversations/#{convo.id}", headers: auth_headers_for(admin)

      usage = response.parsed_body["usage"]
      # Lifetime, and per-turn beside it — the footer used to show only
      # the first and label it next to per-run token counts.
      expect(usage["cost_cents"]).to eq(34)
      expect(usage.dig("last_run", "cost_cents")).to eq(1)
      expect(usage.dig("last_run", "cache_read_tokens")).to eq(7_550)
      # Stored since C3 and never surfaced until now, which hid the most
      # expensive token class (1.25× input).
      expect(usage.dig("last_run", "cache_write_tokens")).to eq(1_200)
      expect(usage.dig("last_run", "outcome")).to eq("done")
    end

    # The reported symptom, exactly: "203¢ total · 0 rounds · 0 cached ·
    # 0 in / 0 out · 0.1s · error". Nothing was reset — a turn refused
    # before its first round still acquires a run, and `enforce_budget!`
    # raises before any HTTP call, so the row is released all-zeros and
    # the serializer was reading *that* as the last run. The numbers come
    # from the last run that has any now, and the refusal travels
    # separately.
    it "keeps the last working run's numbers when a later turn is refused" do
      admin = create(:user, :admin)
      convo = create(:conversation, user: admin, spent_cents: 203)

      worked = ConversationRun.acquire(convo)
      worked.record_round!({ "input_tokens" => 1_200, "output_tokens" => 400,
                             "cache_read_input_tokens" => 7_550 },
                           model: Chat::AgentLoop::MODEL)
      worked.release!(outcome: "done")

      refused = ConversationRun.acquire(convo)
      refused.release!(outcome: "error", state: "failed")

      get "/api/v1/conversations/#{convo.id}", headers: auth_headers_for(admin)

      usage = response.parsed_body["usage"]
      expect(usage.dig("last_run", "rounds")).to eq(1)
      expect(usage.dig("last_run", "input_tokens")).to eq(1_200)
      expect(usage.dig("last_run", "cache_read_tokens")).to eq(7_550)
      # And the refusal is still reported — it just is not the run the
      # tokens came from.
      expect(usage.dig("last_outcome", "outcome")).to eq("error")
      expect(usage.dig("last_outcome", "state")).to eq("failed")
    end

    it "reports no run at all when none has ever done work" do
      admin = create(:user, :admin)
      convo = create(:conversation, user: admin)
      ConversationRun.acquire(convo).release!(outcome: "nothing_queued")

      get "/api/v1/conversations/#{convo.id}", headers: auth_headers_for(admin)

      usage = response.parsed_body["usage"]
      expect(usage["last_run"]).to be_nil
      expect(usage.dig("last_outcome", "outcome")).to eq("nothing_queued")
    end

    it "reads as empty rather than broken before any turn has run" do
      admin = create(:user, is_admin: true)
      convo = create(:conversation, user: admin)

      get "/api/v1/conversations/#{convo.id}", headers: auth_headers_for(admin)

      expect(response.parsed_body["usage"]["last_run"]).to be_nil
    end
  end

  # React Native's fetch is XHR-backed and exposes no readable body, so the
  # mobile app cannot consume the SSE stream. The events are rows either
  # way — the relay is just a long-lived reader over this same table.
  describe "GET /api/v1/conversations/:id/events" do
    let(:conversation) { create(:conversation, user: user) }

    def append(payload)
      run = ConversationRun.running.find_by(conversation_id: conversation.id) ||
            ConversationRun.acquire(conversation)
      ConversationEvent.append!(run, payload)
    end

    it "returns the narration with the cursor a client resumes from" do
      append({ "type" => "text_delta", "text" => "Reading" })
      append({ "type" => "done", "text" => "Reading the menu." })

      get "/api/v1/conversations/#{conversation.id}/events", headers: headers

      events = response.parsed_body["events"]
      expect(events.map { |e| e["type"] }).to eq(%w[text_delta done])
      expect(events.last["position"]).to eq(2)
    end

    # The same cursor the stream uses, so a client can move between the
    # two without losing its place.
    it "returns only what comes after the cursor" do
      append({ "type" => "text_delta", "text" => "one" })
      append({ "type" => "text_delta", "text" => "two" })

      get "/api/v1/conversations/#{conversation.id}/events?after=1", headers: headers

      expect(response.parsed_body["events"].map { |e| e["text"] }).to eq(["two"])
    end

    # Saves a client polling a finished conversation forever.
    it "says whether it is worth asking again" do
      ConversationRun.acquire(conversation)

      get "/api/v1/conversations/#{conversation.id}/events", headers: headers
      expect(response.parsed_body["running"]).to be(true)

      ConversationRun.running.find_by(conversation_id: conversation.id).release!(outcome: "done")

      get "/api/v1/conversations/#{conversation.id}/events", headers: headers
      expect(response.parsed_body["running"]).to be(false)
    end

    it "404s another account's conversation" do
      other = create(:conversation, user: create(:user))

      get "/api/v1/conversations/#{other.id}/events", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end

