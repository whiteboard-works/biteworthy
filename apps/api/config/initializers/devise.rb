# Minimal Devise config for API-mode + JWT.
# Full options remain at the Devise defaults; everything routed through
# config/routes.rb's devise_for inside the api/v1 namespace.

Devise.setup do |config|
  config.mailer_sender = ENV.fetch("DEVISE_MAILER_FROM", "no-reply@biteworthy.app")

  require "devise/orm/active_record"

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]

  config.skip_session_storage = [:http_auth, :params_auth]
  config.stretches = Rails.env.test? ? 1 : 12

  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 8..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/

  config.reset_password_within = 6.hours
  config.sign_out_via = :delete

  config.navigational_formats = []  # API-only

  # Tell Devise that signup/login/logout/refresh hand back JSON, not
  # redirects. Without this Devise tries to render flash + Location
  # headers for navigational requests and 401s for everything else.
  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other

  # OmniAuth providers — credentials come from ENV (see apps/api/.env.example).
  # Both strategies are registered unconditionally so route helpers
  # (`user_google_oauth2_omniauth_authorize_path`, etc.) exist in
  # every environment; missing ENV just means the live OAuth handshake
  # 401s, which is what we want during local dev without keys.
  config.omniauth :google_oauth2,
                  ENV["GOOGLE_OAUTH_CLIENT_ID"],
                  ENV["GOOGLE_OAUTH_CLIENT_SECRET"],
                  scope: "email,profile",
                  prompt: "select_account"

  config.omniauth :apple,
                  ENV["APPLE_OAUTH_CLIENT_ID"],
                  "", # client_secret is generated from the private key, not an env var
                  scope: "email name",
                  team_id: ENV["APPLE_OAUTH_TEAM_ID"],
                  key_id: ENV["APPLE_OAUTH_KEY_ID"],
                  pem: ENV["APPLE_OAUTH_PRIVATE_KEY"]
end
