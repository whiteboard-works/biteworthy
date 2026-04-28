require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  config.active_storage.service = :amazon

  config.force_ssl = true
  config.assume_ssl = true

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)

  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue
  config.active_record.dump_schema_after_migration = false

  config.action_mailer.perform_caching = false

  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
end
