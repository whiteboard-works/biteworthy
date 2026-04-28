ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# Ruby 3.3 + bundled_gems: actionview reopens stdlib's ERB class and
# expects ENCODING_FLAG to already be defined. Forcing erb to load
# before bundler's require chain dodges the NameError seen with
# rspec-rails 7.1.x in CI.
require "erb"

require "bundler/setup"
require "bootsnap/setup"
