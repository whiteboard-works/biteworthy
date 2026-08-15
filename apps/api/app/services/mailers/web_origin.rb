# The web app's public origin, for mailer templates that link web pages
# (not API routes). One place instead of per-template ENV reads, and the
# fallback is dev-safe: a reset email minted against a local database
# must not send its user to production with a token prod never issued.
module Mailers
  module WebOrigin
    def self.base
      opts = ActionMailer::Base.default_url_options || {}
      if opts[:host].present?
        protocol = opts[:protocol] || "https"
        port     = opts[:port].present? ? ":#{opts[:port]}" : ""
        "#{protocol}://#{opts[:host]}#{port}"
      else
        ENV.fetch("MAILER_HOST", "http://localhost:3001")
      end
    end

    def self.reset_password_url(token)
      "#{base.chomp('/')}/reset-password?reset_password_token=#{token}"
    end
  end
end
