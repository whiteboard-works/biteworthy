require "vcr"
require "webmock/rspec"

VCR.configure do |c|
  c.cassette_library_dir       = Rails.root.join("spec/cassettes").to_s
  c.hook_into                  :webmock
  c.configure_rspec_metadata!
  c.allow_http_connections_when_no_cassette = false

  # Anthropic creds get scrubbed before cassettes are written.
  c.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  c.filter_sensitive_data("<X_API_KEY_HEADER>") do |interaction|
    interaction.request.headers["X-Api-Key"]&.first
  end

  # CI runs replay-only — no live calls allowed even by accident.
  c.default_cassette_options = {
    record: ENV["CI"] ? :none : :once,
    match_requests_on: [:method, :uri, :body]
  }
end
