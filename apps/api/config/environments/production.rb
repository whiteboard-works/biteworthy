require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  # Phase 5.3 — production blobs live on Cloudflare R2 (ADR 0004).
  # `:amazon` (AWS S3) stays in storage.yml as a no-code-change
  # fallback — flip this back if R2 ever has a regional outage.
  config.active_storage.service = :r2

  config.force_ssl = true
  config.assume_ssl = true

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)

  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue
  config.active_record.dump_schema_after_migration = false

  config.action_mailer.perform_caching = false

  # Phase 5.2 — production SMTP. Provider-agnostic: any SMTP-capable
  # service (Postmark, SES, SendGrid, Mailgun) works by setting the
  # SMTP_* env vars via `fly secrets set`. ADR 0003 documents the
  # Postmark pick + alternatives.
  #
  # Fail loudly if delivery raises — Solid Queue retries the mailer
  # job on transient errors, but a misconfigured server should NOT
  # silently swallow signups. Disable raise_delivery_errors only
  # if a hosted-by-Fly outage requires it (rare).
  config.action_mailer.delivery_method   = :smtp
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries    = true
  config.action_mailer.smtp_settings = {
    address:              ENV.fetch("SMTP_ADDRESS", "smtp.postmarkapp.com"),
    port:                 ENV.fetch("SMTP_PORT", "587").to_i,
    user_name:            ENV["SMTP_USERNAME"],
    password:             ENV["SMTP_PASSWORD"],
    domain:               ENV.fetch("SMTP_DOMAIN", "bite-worthy.com"),
    authentication:       :plain,
    enable_starttls_auto: true
  }
  # Mailers build full URLs (claim verify links, password resets) —
  # MAILER_HOST is the public host the user clicks back into.
  # Mirrors PUBLIC_HOST except mailers point at the WEB origin
  # (bite-worthy.com), not the API origin.
  mailer_host = ENV.fetch("MAILER_HOST", "https://bite-worthy.com")
  uri         = URI.parse(mailer_host)
  config.action_mailer.default_url_options = {
    host:     uri.host,
    port:     uri.port == uri.default_port ? nil : uri.port,
    protocol: uri.scheme
  }.compact
  Rails.application.routes.default_url_options = config.action_mailer.default_url_options

  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
end
