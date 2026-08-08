# frozen_string_literal: true

# The two documents that let an MCP client authorize itself without anyone
# configuring it.
#
# The discovery chain is: the client POSTs /mcp with no credential, gets a
# 401 carrying `WWW-Authenticate: Bearer resource_metadata="…"`, fetches
# that document (RFC 9728) to learn which authorization server guards this
# resource, fetches *its* metadata (RFC 8414) to learn the endpoints, then
# registers or is preconfigured and runs the code flow. Nothing in that
# path involves a person copying a URL.
#
# Both are public and unauthenticated by definition — they are what a
# client reads *before* it has a credential.
class OauthMetadataController < ApplicationController
  # RFC 9728. "This resource is guarded by that authorization server."
  def protected_resource
    render json: {
      resource:                 mcp_resource,
      authorization_servers:    [issuer],
      scopes_supported:         Tools::Scopes.available,
      bearer_methods_supported: ["header"],
      resource_name:            "Biteworthy",
      resource_documentation:   "#{issuer}/mcp"
    }
  end

  # RFC 8414. The endpoints and what they accept.
  def authorization_server
    render json: {
      issuer:                                issuer,
      authorization_endpoint:                "#{issuer}/oauth/authorize",
      token_endpoint:                        "#{issuer}/oauth/token",
      revocation_endpoint:                   "#{issuer}/oauth/revoke",
      scopes_supported:                      Tools::Scopes.available,
      response_types_supported:              ["code"],
      grant_types_supported:                 %w[authorization_code refresh_token],
      # Public clients only — a desktop MCP client cannot keep a secret,
      # which is exactly why PKCE is mandatory below.
      token_endpoint_auth_methods_supported: ["none"],
      code_challenge_methods_supported:      Doorkeeper.config.pkce_code_challenge_methods_supported,
      # RFC 8707. A client should ask for a token audienced to this
      # resource rather than one good everywhere.
      resource_indicators_supported:         true
    }
  end

  private

  # PUBLIC_HOST in production, because a client fetching from a different
  # origin must be told the origin it should actually call.
  def issuer
    ENV["PUBLIC_HOST"].presence || request.base_url
  end

  def mcp_resource
    "#{issuer}/mcp"
  end
end
