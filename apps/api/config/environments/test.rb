require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{1.hour.to_i}" }

  config.consider_all_requests_local = true
  config.cache_store = :null_store

  config.active_storage.service = :test

  config.action_mailer.delivery_method = :test
  config.action_mailer.perform_caching = false
  config.action_mailer.raise_delivery_errors = true

  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise

  config.action_controller.raise_on_missing_callback_actions = true
end
