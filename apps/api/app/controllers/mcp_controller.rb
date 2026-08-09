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

  # Declared rather than defaulted, because passing `capabilities:`
  # replaces the gem's defaults wholesale — and because two of those
  # defaults are wrong for this server.
  #
  # `listChanged` is deliberately absent: it promises a
  # `notifications/*/list_changed` when the catalogue changes, and a
  # stateless transport has no channel to send one on. The gem defaults it
  # to true, so until now every client was told to expect a message that
  # could never arrive. The lists *do* change per caller — scope and
  # audience filter them — which is exactly why claiming to announce it
  # matters.
  #
  # `completions` is the new one: a client only offers argument
  # autocompletion if the server says it can answer.
  CAPABILITIES = {
    tools:       {},
    prompts:     {},
    resources:   {},
    completions: {},
    logging:     {}
  }.freeze

  def handle
    return unauthorized if authorization_failed?

    context = Tools::Context.new(server_context)

    status, headers, body = transport_for(context).handle_request(request)

    headers.each { |name, value| response.set_header(name, value) unless name.casecmp("content-type").zero? }
    render plain: Array(body).join,
           status: status,
           content_type: headers["content-type"] || "application/json"
  end

  private

  def transport_for(context)
    server = MCP::Server.new(
      name:           SERVER_NAME,
      title:          "Biteworthy",
      version:        SERVER_VERSION,
      instructions:   Tools::Instructions.text,
      tools:          Tools::Registry.for(context),
      # The tool map, so a client that reads resources can learn how the
      # tools compose without spending a turn on describe_capabilities.
      resources:      [Tools::TopologyResource],
      # A menu a person can *attach*, the way they attach a file, instead
      # of hoping the model reaches for get_menu. Same filter underneath,
      # so an attachment is this reader's menu — hidden dishes included,
      # each carrying its reason.
      resource_templates: [Tools::MenuResource],
      # The same workflows as things a person can pick before typing —
      # "Scan a menu into the database" beats a blank box and 44 tools.
      # Generated from the topology, so they cannot drift from it.
      prompts:        Tools::WorkflowPrompts.for(context),
      capabilities:   CAPABILITIES,
      server_context: server_context
    )

    # Slugs are the one thing nobody can guess — `search_taxonomy` exists
    # because a model cannot turn "garbanzo" into `chickpea`, and a person
    # filling in a prompt argument is in the same position with a blank
    # box. The gem's default handler answers every completion with an
    # empty list.
    #
    # The prompt in `ref` is looked up in this server's own prompt list,
    # which `WorkflowPrompts.for` already filtered to this caller — so a
    # workflow someone cannot run cannot be completed against either,
    # without a second rule here that would drift from the first.
    server.completion_handler do |params|
      Tools::Completions.call(
        argument_name: params.dig(:argument, :name),
        value:         params.dig(:argument, :value)
      )
    end

    MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
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
      user_id:     caller_user&.id,
      public_host: public_host,
      request_id:  request.request_id,
      # Empty for a plain JWT, which carries every power the account has.
      # A scoped credential narrows that, and the tool layer enforces it —
      # in the JSON-RPC result, not as an HTTP 403, because the *request*
      # authenticated fine and only one tool call was out of bounds.
      scopes:      granted_scopes
    }
  end

  # Three credentials reach this door, in order of how they were obtained.
  # An OAuth access token is what a client gets on its own, with no person
  # in a terminal; a `bw_mcp_` token is the same least-privilege shape but
  # issued by hand; the Devise JWT is the whole account and is what the
  # first-party clients already hold.
  def caller_user
    return @caller_user if defined?(@caller_user)

    @caller_user = oauth_user || mcp_token&.user || current_user
  end

  # Doorkeeper stores `resource_owner_id` rather than an association —
  # the polymorphic owner is an opt-in we do not need, since every grant
  # here belongs to a User.
  def oauth_user
    return nil if oauth_token.nil?

    @oauth_user ||= User.find_by(id: oauth_token.resource_owner_id)
  end

  # Doorkeeper stores tokens hashed (see the initializer), so the lookup
  # goes through `by_token` rather than a where on the column.
  def oauth_token
    return @oauth_token if defined?(@oauth_token)

    @oauth_token = bearer_secret.present? ? Doorkeeper::AccessToken.by_token(bearer_secret) : nil
    @oauth_token = nil unless @oauth_token&.accessible?
    @oauth_token
  end

  def mcp_token
    return @mcp_token if defined?(@mcp_token)

    @mcp_token = McpToken.authenticate(bearer_secret)
    @mcp_token&.note_use!
    @mcp_token
  end

  def bearer_secret
    request.authorization.to_s[/\ABearer (.+)\z/i, 1]
  end

  # Devise's `current_user` returns nil rather than raising when the token
  # is missing or bad, so "was a token offered?" and "did it work?" have to
  # be asked separately. A `bw_mcp_` secret that resolves is also a pass —
  # it is a different credential, not a malformed JWT.
  def authorization_failed?
    request.authorization.present? && caller_user.nil?
  end

  def granted_scopes
    oauth_token&.scopes&.to_a || mcp_token&.scopes || []
  end

  # `resource_metadata` is the RFC 9728 pointer that turns a 401 into a
  # client that can authorize itself: it reads the document, learns which
  # authorization server guards this resource, and runs the code flow —
  # no one pastes a token anywhere.
  def unauthorized
    response.set_header(
      "WWW-Authenticate",
      %(Bearer realm="#{SERVER_NAME}", error="invalid_token", ) +
      %(resource_metadata="#{public_host}/.well-known/oauth-protected-resource/mcp")
    )
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
