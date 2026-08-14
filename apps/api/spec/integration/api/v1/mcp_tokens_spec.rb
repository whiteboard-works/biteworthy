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
                  "client need not hardcode the vocabulary, and `full_access_scope` names " \
                  "the one that grants everything."
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "active tokens and the grantable scopes") do
        schema type: :object,
               required: %w[tokens scopes full_access_scope],
               properties: {
                 tokens: { type: :array, items: { "$ref" => "#/components/schemas/McpToken" } },
                 scopes: { type: :array, items: { type: :string } },
                 full_access_scope: {
                   type: :string,
                   description: "Grants everything the account can do. Not included in " \
                                "`scopes`, because it is a different kind of choice."
                 }
               }
        before { McpToken.issue!(user: account, name: "Claude Code", scopes: ["discovery:read"]) }
        run_test!
      end
    end

    post("Issue a scoped MCP token") do
      tags "MCP"
      description "The only response that ever carries the secret. `scopes` is required " \
                  "and must name at least one grant; send the `full_access_scope` from " \
                  "GET to grant everything the account can do."
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[name scopes],
        properties: {
          name:   { type: :string, maxLength: 60 },
          scopes: {
            type: :array, items: { type: :string }, minItems: 1,
            description: "e.g. discovery:read. An empty list is refused rather than " \
                         "read as full access — see full_access_scope."
          }
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
        let(:id) { McpToken.issue!(user: account, name: "old laptop", scopes: ["discovery:read"]).first.id }
        run_test!
      end

      response(404, "another account's token") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) { McpToken.issue!(user: create(:user), name: "theirs", scopes: ["discovery:read"]).first.id }
        run_test!
      end
    end
  end
end
