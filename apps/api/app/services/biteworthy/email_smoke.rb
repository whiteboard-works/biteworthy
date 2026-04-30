# frozen_string_literal: true

# Phase 5.2 — production SMTP smoke runner.
#
# Sends a single test message to the configured EMAIL= recipient and
# reports the Message-ID. Wrapped by `bin/rails biteworthy:email:smoke`.
#
# Two modes:
#
#   * **production** — `delivery_method = :smtp` from
#     `config/environments/production.rb` opens a real SMTP connection.
#     Useful right after `fly secrets set SMTP_*=...` to confirm
#     Postmark (or whichever provider) accepts the credentials.
#
#   * **dev / test** — `:test` adapter captures the message in
#     `ActionMailer::Base.deliveries`. The runner reports the Message-ID
#     anyway so the same code path is exercised. CI runs the spec
#     against this mode.
#
# Returns true on success (delivery raised no error). Does NOT block
# the task on Postmark response codes — the SMTP server's 250 OK is
# already the success signal; reading further would require the
# provider's REST API.
module Biteworthy
  class EmailSmoke
    def initialize(to:, logger:, mailer: BiteworthyMailer)
      @to     = to
      @logger = logger
      @mailer = mailer
    end

    def run
      @logger.puts "BiteWorthy SMTP smoke → #{@to}"
      @logger.puts "  delivery_method=#{ActionMailer::Base.delivery_method.inspect}"
      @logger.puts "  smtp_address=#{ActionMailer::Base.smtp_settings[:address].inspect}" if smtp?

      message = @mailer.smoke_test(to: @to).deliver_now

      @logger.puts "  → delivered  Message-ID=#{message.message_id}"
      true
    rescue StandardError => e
      @logger.puts "  → FAILED  #{e.class}: #{e.message}"
      false
    end

    private

    def smtp?
      ActionMailer::Base.delivery_method == :smtp
    end
  end
end
