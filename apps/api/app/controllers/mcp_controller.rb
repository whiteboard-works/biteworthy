# frozen_string_literal: true

# The MCP front door: POST /mcp.
#
# Exposes app/services/tools/* over Streamable HTTP so Claude Desktop and
# Claude Code can drive Biteworthy directly. The same tool classes back the
# first-party chat, so this controller stays a transport adapter — no
# domain logic, no authorization decisions beyond resolving who is calling.
#
# **Stateless by design.** The transport's stateful mode keeps sessions in
# process memory, which breaks the moment Puma runs more than one worker or
# Kamal rolls a second container. Stateless mode makes every POST
# self-contained, at the cost of no server-initiated notifications — which
# we do not use.
#
# Auth today is the same Devise JWT the REST API issues:
#
#     Authorization: Bearer <jwt>
#
# No header means an anonymous caller, who still gets the public discovery
# tools. A header that fails to authenticate is a 401 rather than a silent
# downgrade to anonymous — a client with a stale token needs to know to
# refresh it, not to quietly lose its own data.
#
# Public distribution (the claude.ai connector directory) needs OAuth 2.1
# plus RFC 9728 protected-resource metadata; see docs/mcp.md.
class McpController < ApplicationController
  SERVER_NAME    = "biteworthy"
  SERVER_VERSION = "1.0.0"

  def handle
    context = Tools::Context.new(server_context)
    return unauthorized if authorization_failed?

    status, headers, body = transport_for(context).handle_request(request)

    headers.each { |name, value| response.set_header(name, value) unless name.casecmp("content-type").zero? }
    render plain: Array(body).join,
           status: status,
           content_type: headers["content-type"] || "application/json"
  end

  private

  def transport_for(context)
    MCP::Server::Transports::StreamableHTTPTransport.new(
      MCP::Server.new(
        name:           SERVER_NAME,
        title:          "Biteworthy",
        version:        SERVER_VERSION,
        instructions:   Tools::Instructions.text,
        tools:          Tools::Registry.for(context),
        # The tool map, so a client that reads resources can learn how the
        # tools compose without spending a turn on describe_capabilities.
        resources:      [Tools::TopologyResource],
        # The same workflows as things a person can pick before typing —
        # "Scan a menu into the database" beats a blank box and 44 tools.
        # Generated from the topology, so they cannot drift from it.
        prompts:        Tools::WorkflowPrompts.for(context),
        server_context: server_context
      ),
      stateless: true,
      # The transport's DNS-rebinding guard allow-lists loopback and 403s
      # every other Host, which would reject every production request.
      # Rails' own host authorization (config.hosts) has already vetted
      # Host by the time a request reaches this controller, so re-listing
      # it here would duplicate a list Rails owns. Trusting the vetted host
      # keeps the guard's Origin check — the half that actually stops a
      # browser cross-origin POST — fully in force.
      allowed_hosts: [request.host],
      allowed_origins: allowed_origins
    )
  end

  # A plain Hash — MCP::ServerContext forwards unknown methods to it, so
  # tools can read it with `[]` / `dig`.
  def server_context
    @server_context ||= {
      user_id:     current_user&.id,
      public_host: public_host,
      request_id:  request.request_id
    }
  end

  # Devise's `current_user` returns nil rather than raising when the token
  # is missing or bad, so "was a token offered?" and "did it work?" have to
  # be asked separately.
  def authorization_failed?
    request.authorization.present? && current_user.nil?
  end

  def unauthorized
    response.set_header("WWW-Authenticate", %(Bearer realm="#{SERVER_NAME}", error="invalid_token"))
    render json: {
      jsonrpc: "2.0",
      error: { code: -32_001, message: "Invalid or expired access token." },
      id: nil
    }, status: :unauthorized
  end

  # Same-origin requests are allowed by the transport without listing.
  # WEB_ORIGIN is the browser app talking to a different API host, which is
  # cross-origin and therefore does need naming.
  def allowed_origins
    ENV["WEB_ORIGIN"].to_s.split(",").map(&:strip).compact_blank
  end

  def public_host
    ENV["PUBLIC_HOST"].presence || request.base_url
  end
end
