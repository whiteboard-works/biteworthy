# frozen_string_literal: true

# RFC 7591 dynamic client registration.
#
# Without this, using the MCP server means a person emailing us for a
# client id, which is exactly the friction M8 exists to remove: a client
# in a connector directory has no one to ask. It registers itself, gets an
# id, and runs the code flow.
#
# **Registration is unauthenticated by design** — that is what "dynamic"
# means, and the spec's open registration profile. What keeps it safe is
# that a client id grants nothing on its own: it names an app, and every
# authorization still goes through a person approving specific scopes on
# the consent screen. The risks it does carry are row creation (rate
# limited in config/initializers/rack_attack.rb) and phishable display
# names (the consent screen shows the redirect URI alongside the name, so
# an app calling itself "Biteworthy" cannot hide where it sends you).
class OauthRegistrationsController < ApplicationController
  # Public clients only. A secret handed out over an unauthenticated
  # endpoint protects nothing, so PKCE does the work instead.
  AUTH_METHOD = "none"
  MAX_REDIRECT_URIS = 5

  def create
    uris = Array(params[:redirect_uris]).map(&:to_s).compact_blank
    return invalid("redirect_uris is required.") if uris.empty?
    return invalid("At most #{MAX_REDIRECT_URIS} redirect_uris.") if uris.size > MAX_REDIRECT_URIS

    bad = uris.reject { |uri| valid_redirect_uri?(uri) }
    return invalid("Unusable redirect_uri: #{bad.join(', ')}.") if bad.any?

    scopes = params[:scope].to_s.split
    unknown = scopes.reject { |s| Tools::Scopes.valid?(s) }
    # A scope this server does not grant is a client bug worth reporting
    # at registration rather than silently dropping and failing later at
    # authorize, where the person is already staring at a consent screen.
    if unknown.any?
      return render json: { error: "invalid_client_metadata",
                            error_description: "Unknown scope(s): #{unknown.join(', ')}." },
                    status: :bad_request
    end

    app = Doorkeeper::Application.create!(
      name:         client_name,
      redirect_uri: uris.join("\n"),
      scopes:       (scopes.presence || Doorkeeper.config.default_scopes.to_a).join(" "),
      confidential: false
    )

    render json: serialize(app), status: :created
  end

  private

  # A blank name would render as an empty consent screen, which is worse
  # than an obviously unnamed client.
  def client_name
    params[:client_name].to_s.strip.presence&.truncate(100) || "Unnamed MCP client"
  end

  # RFC 8252: a native client redirects either to loopback or to a
  # private-use scheme it owns. Everything else must be https — an http
  # redirect on a public host would put the authorization code on the
  # wire in clear.
  def valid_redirect_uri?(value)
    uri = URI.parse(value)
    return false if uri.scheme.blank?
    return true  if uri.scheme == "https" && uri.host.present?
    return true  if uri.scheme == "http" && loopback?(uri.host)

    # Reverse-DNS, so it is a scheme the client plausibly owns. A bare
    # "myapp:" would collide with every other app claiming it.
    uri.scheme.include?(".")
  rescue URI::InvalidURIError
    false
  end

  def loopback?(host)
    ["localhost", "127.0.0.1", "::1", "[::1]"].include?(host)
  end

  def serialize(app)
    {
      client_id:                  app.uid,
      client_id_issued_at:        app.created_at.to_i,
      client_name:                app.name,
      redirect_uris:              app.redirect_uri.split("\n"),
      grant_types:                %w[authorization_code refresh_token],
      response_types:             ["code"],
      token_endpoint_auth_method: AUTH_METHOD,
      scope:                      app.scopes.to_s
    }
  end

  def invalid(description)
    render json: { error: "invalid_redirect_uri", error_description: description },
           status: :bad_request
  end
end
