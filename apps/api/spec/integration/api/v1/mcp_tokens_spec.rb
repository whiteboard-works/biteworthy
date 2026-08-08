require "swagger_helper"

RSpec.describe "mcp_tokens", type: :request do
  let(:account) { create(:user, password: "password123") }
  let(:Authorization) do
    token, = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/mcp_tokens" do
    get("List the caller's active MCP tokens") do
      tags "MCP"
      description "Never carries a secret — only the digest is stored, so there is nothing " \
                  "an endpoint could return. `scopes` lists every grantable scope so a " \
                  "client need not hardcode the vocabulary."
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "active tokens and the grantable scopes") do
        schema type: :object,
               required: %w[tokens scopes],
               properties: {
                 tokens: { type: :array, items: { "$ref" => "#/components/schemas/McpToken" } },
                 scopes: { type: :array, items: { type: :string } }
               }
        before { McpToken.issue!(user: account, name: "Claude Code", scopes: ["discovery:read"]) }
        run_test!
      end
    end

    post("Issue a scoped MCP token") do
      tags "MCP"
      description "The only response that ever carries the secret. Omit `scopes` for a " \
                  "credential with the same access as the account."
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[name],
        properties: {
          name:   { type: :string, maxLength: 60 },
          scopes: { type: :array, items: { type: :string }, description: "e.g. discovery:read" }
        }
      }

      response(201, "the token, with its one-time secret") do
        schema "$ref" => "#/components/schemas/McpToken"
        let(:body) { { name: "Claude Code", scopes: ["discovery:read"] } }
        run_test!
      end

      response(422, "unknown scope, missing name, or too many active tokens") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:body) { { name: "x", scopes: ["menus:teleport"] } }
        run_test!
      end
    end
  end

  path "/api/v1/mcp_tokens/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete("Revoke one token, without ending other sessions") do
      tags "MCP"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(204, "revoked") do
        let(:id) { McpToken.issue!(user: account, name: "old laptop").first.id }
        run_test!
      end

      response(404, "another account's token") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) { McpToken.issue!(user: create(:user), name: "theirs").first.id }
        run_test!
      end
    end
  end
end
