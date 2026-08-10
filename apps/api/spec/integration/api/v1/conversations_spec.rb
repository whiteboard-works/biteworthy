require "swagger_helper"

# The chat's HTTP surface. These are the source of `docs/openapi.json` and
# therefore of `packages/api-types` — the web and mobile chat clients hand-
# wrote their types until this existed, which is exactly the drift the
# generated-types rule is meant to prevent.
RSpec.describe "conversations", type: :request do
  let(:account) { create(:user, password: "password123") }
  let(:Authorization) do
    token, = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/conversations" do
    get("List the caller's conversations, newest first") do
      tags "Chat"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "the caller's conversations") do
        schema type: :object,
               required: %w[conversations],
               properties: {
                 conversations: { type: :array, items: { "$ref" => "#/components/schemas/Conversation" } }
               }
        before { create(:conversation, user: account, title: "What can I eat at Ninis?") }
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        run_test!
      end
    end

    post("Open an empty conversation") do
      tags "Chat"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(201, "the new conversation") do
        schema "$ref" => "#/components/schemas/Conversation"
        run_test!
      end
    end
  end

  path "/api/v1/conversations/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get("Replay a conversation") do
      tags "Chat"
      description "The reconnect path: a dropped stream loses nothing, because every turn " \
                  "is persisted as it runs. `usage` is present only for admins."
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "the conversation and its transcript") do
        schema "$ref" => "#/components/schemas/Conversation"
        let(:id) { create(:conversation, user: account).id }
        run_test!
      end

      response(404, "another account's conversation") do
        let(:id) { create(:conversation, user: create(:user)).id }
        run_test!
      end
    end

    patch("Switch the conversation's mode") do
      tags "Chat"
      description "For switching without sending anything, so the picker survives a " \
                  "reload. A turn carries the mode it was sent under, so this sets what " \
                  "the *next* send will use — it does not change a turn already running."
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[mode],
        properties: {
          mode: { type: :string, enum: %w[planning manual accept_edits auto] }
        }
      }

      response(200, "the conversation, with the new mode") do
        schema "$ref" => "#/components/schemas/Conversation"
        let(:id)   { create(:conversation, user: account).id }
        let(:body) { { mode: "planning" } }
        run_test!
      end

      response(422, "a mode that does not exist") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id)   { create(:conversation, user: account).id }
        let(:body) { { mode: "yolo" } }
        run_test!
      end
    end

    delete("Delete a conversation and its transcript") do
      tags "Chat"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(204, "deleted") do
        let(:id) { create(:conversation, user: account).id }
        run_test!
      end
    end
  end

  path "/api/v1/conversations/{id}/messages" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post("Ask for a turn") do
      tags "Chat"
      description "Records the request and hands off to a background job — no model call " \
                  "happens in this request. Watch the narration with /stream or /events."
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[message],
        properties: {
          message: { type: :string, maxLength: 20_000 },
          mode: {
            type: :string,
            enum: %w[planning manual accept_edits auto],
            description: "Switch mode and send in one request, so the picker cannot lose " \
                         "a race with the message it was changed for. Omit to keep the " \
                         "conversation's current mode."
          },
          context: {
            type: :object,
            description: "Where the user is standing, so \"what can I eat here\" is answerable.",
            properties: { path: { type: :string }, restaurant: { type: :string } }
          }
        }
      }

      response(202, "queued") do
        schema "$ref" => "#/components/schemas/TurnQueued"
        let(:id)   { create(:conversation, user: account).id }
        let(:body) { { message: "What can I eat at Ninis?" } }
        run_test!
      end

      response(422, "empty or over-long message") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id)   { create(:conversation, user: account).id }
        let(:body) { { message: "  " } }
        run_test!
      end

      response(409, "a confirmation is still parked") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) do
          create(:conversation, user: account, state: "awaiting_confirmation",
                                pending_tool_call: { "results" => [], "queue" => [{ "name" => "delete_review" }] }).id
        end
        let(:body) { { message: "never mind" } }
        run_test!
      end
    end
  end

  path "/api/v1/conversations/{id}/confirm" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post("Answer a parked destructive call") do
      tags "Chat"
      description "`fingerprint` binds the answer to the call that was drawn, so a stale " \
                  "client cannot approve whatever happens to be parked now."
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[confirm],
        properties: {
          confirm:     { type: :boolean },
          fingerprint: { type: :string, nullable: true },
          mode:        { type: :string, enum: %w[planning manual accept_edits auto] }
        }
      }

      response(409, "nothing is waiting") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id)   { create(:conversation, user: account).id }
        let(:body) { { confirm: true } }
        run_test!
      end
    end
  end

  path "/api/v1/conversations/{id}/events" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true
    parameter name: :after, in: :query, type: :integer, required: false,
              description: "Narration cursor. Same one /stream uses."

    get("Read a turn's narration as JSON") do
      tags "Chat"
      description "For clients that cannot hold a stream open — React Native's fetch " \
                  "exposes no readable body. Poll while `running` is true."
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "narration after the cursor") do
        schema "$ref" => "#/components/schemas/ChatEventsPage"
        let(:id)    { create(:conversation, user: account).id }
        let(:after) { 0 }
        run_test!
      end
    end
  end

  path "/api/v1/conversations/{id}/run" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete("Stop the running turn") do
      tags "Chat"
      description "Raises a flag the turn reads at its next checkpoint. Necessarily a " \
                  "separate request from the one that started it."
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(409, "nothing is running") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) { create(:conversation, user: account).id }
        run_test!
      end
    end
  end
end
