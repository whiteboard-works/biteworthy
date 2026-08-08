# frozen_string_literal: true

# OAuth 2.1 authorization server, for MCP clients that cannot be handed a
# long-lived credential by a person.
#
# **Consent renders in apps/web, not here.** This app is `api_only` and has
# no notion of a logged-in browser: the session cookie exists solely to
# carry OmniAuth's `state`, and the JWT lives in an httpOnly cookie owned
# by the web origin that a browser never sends here. Rendering consent in
# Rails would mean building a second login surface — a second place to get
# rate limiting, lockout and password reset right — in a codebase that
# deliberately has exactly one.
#
# So the flow hands off:
#
#   1. The client sends a browser to GET /oauth/authorize.
#   2. No handoff present → redirect to the web app's consent page,
#      carrying the original authorize URL.
#   3. The web app knows who is signed in. On approve it asks the API for
#      a short-lived handoff token and returns the browser to the same
#      authorize URL with it attached.
#   4. The token names the user *and* is bound to a digest of the exact
#      authorize parameters, so a grant can only be issued for the request
#      the person was actually shown. Same principle as the chat's
#      confirmation fingerprint.
#
# Wrapped in `to_prepare` because the scope vocabulary is derived from
# `Tools::Scopes` — an autoloaded constant, and initializers run before
# autoloading. Deriving beats restating: a new tool domain cannot ship
# without an OAuth scope for it.
Rails.application.config.to_prepare do
  Doorkeeper.configure do
    orm :active_record

    # Step 4 above. Returns the user, or sends the browser to consent.
    #
    # `allow_other_host` because consent is on a different origin on
    # purpose. The host comes from WEB_ORIGIN — server config, never a
    # request parameter — so this is not the open redirect the guard is
    # there to catch.
    resource_owner_authenticator do
      Oauth::Handoff.resource_owner_for(request) ||
        redirect_to(Oauth::Handoff.consent_url_for(request), allow_other_host: true)
    end

    # PKCE is the whole protection for a public client, so it is not
    # optional and `plain` — which protects nothing — is not accepted.
    force_pkce
    pkce_code_challenge_methods %w[S256]

    # Only the authorization-code flow. No implicit (removed in OAuth
    # 2.1), no password grant, no client credentials — none of them are
    # "a person granting an app access to their own account".
    grant_flows %w[authorization_code refresh_token]

    # A desktop MCP client cannot keep a secret, so clients are public and
    # the redirect URI is the only thing tying a code back to them.
    allow_blank_redirect_uri false

    # Doorkeeper's blanket https rule is right for the web and wrong for
    # native clients: RFC 8252 says they redirect to loopback, which
    # cannot have a certificate. Loopback never leaves the machine, so
    # there is no hop to intercept. Everything else still must be https —
    # OauthRegistrationsController enforces the same line at the door.
    force_ssl_in_redirect_uri { |uri| !%w[localhost 127.0.0.1 ::1].include?(uri.host) }

    # Scopes are the tool-domain vocabulary McpToken already uses, so a
    # grant and a personal token mean the same thing to `Tools::Base` and
    # there is no second authorization model to keep in step.
    default_scopes :"discovery:read"
    optional_scopes(*Tools::Scopes.available.map(&:to_sym))
    enforce_configured_scopes

    # Short-lived and refreshable. An MCP client holding a year-long token
    # is the thing this exists to avoid.
    access_token_expires_in 2.hours
    use_refresh_token

    # Same reasoning as McpToken#token_digest: a leaked database must not
    # be a leaked set of working credentials.
    hash_token_secrets

    # Consent already happened in the web app and the handoff token binds
    # this request to what was shown there. Re-prompting here would mean
    # rendering a second consent screen from an app with no views.
    skip_authorization { true }

    # An authorization error belongs at the client's redirect URI, where
    # the client is waiting, rather than rendered as a page nobody scripted
    # against. Doorkeeper still refuses to redirect when the error is in
    # the client id or the redirect URI itself — the two cases where the
    # destination cannot be trusted.
    handle_auth_errors :redirect

    # Deliberately NOT `api_only`. It sounds right for this app, and it is
    # wrong here: it turns `/oauth/authorize`'s 302 into a JSON body, which
    # a browser mid-flow cannot follow. What it otherwise buys — skipping
    # the applications UI and its CSRF — we already get from
    # `skip_controllers` in routes.rb and from `skip_authorization`, which
    # means the authorization form is never posted.
  end
end
