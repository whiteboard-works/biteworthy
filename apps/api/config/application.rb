require_relative "boot"

require "rails"
# Pick only what an API needs — drop ActionMailbox, ActionText, etc.
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_cable/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Biteworthy
  class Application < Rails::Application
    config.load_defaults 8.0

    config.api_only = true
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Solid* defaults: queue + cache + cable run on Postgres.
    config.active_job.queue_adapter = :solid_queue
    config.cache_store = :solid_cache_store

    config.autoload_lib(ignore: %w[assets tasks])

    # CORS handled in initializers/cors.rb.
  end
end
