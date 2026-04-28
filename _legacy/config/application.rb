require File.expand_path('../boot', __FILE__)

require 'rails/all'
# require 'config/initializers/string'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Bwd
  class Application < Rails::Application
    config.time_zone = "Mountain Time (US & Canada)"
    config.active_record.default_timezone = :local

    # config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
    config.autoload_paths += %W(#{config.root}/lib)
    config.before_configuration do
      ::Services = OpenStruct.new(YAML.load_file("#{Rails.root}/config/services.yml")[Rails.env])
    end
  end
end
