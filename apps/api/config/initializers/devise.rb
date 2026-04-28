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

  # JWT (devise-jwt) — wired up in a follow-up commit alongside
  # SessionsController. Placeholder here so seeded users have a default
  # `jti`. See app/controllers/api/v1/sessions_controller.rb.
end
