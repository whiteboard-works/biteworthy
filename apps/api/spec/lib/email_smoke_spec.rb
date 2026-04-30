require "rails_helper"
require "stringio"

# Phase 5.2 — guards the SMTP smoke runner the rake task wraps.
# Test-env mailer uses the `:test` adapter so we can introspect
# deliveries without opening a real socket.
RSpec.describe Biteworthy::EmailSmoke do
  let(:logger) { StringIO.new }

  before { ActionMailer::Base.deliveries.clear }

  describe "#run" do
    it "delivers exactly one message via the configured mailer" do
      runner = described_class.new(to: "skylar@example.com", logger: logger)

      expect(runner.run).to be true
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq(["skylar@example.com"])
      expect(ActionMailer::Base.deliveries.last.subject).to start_with("BiteWorthy SMTP smoke test")
    end

    it "logs the recipient + delivery_method + Message-ID" do
      runner = described_class.new(to: "skylar@example.com", logger: logger)

      runner.run

      expect(logger.string).to include("BiteWorthy SMTP smoke → skylar@example.com")
      expect(logger.string).to match(/delivery_method=:test/)
      expect(logger.string).to match(/Message-ID=\S+@\S+/)
    end

    it "returns false + logs FAIL when the mailer raises" do
      flaky = Class.new do
        def self.smoke_test(to:)
          raise Net::SMTPAuthenticationError, "535 bad user/password"
        end
      end
      runner = described_class.new(to: "skylar@example.com", logger: logger, mailer: flaky)

      expect(runner.run).to be false
      expect(logger.string).to include("FAILED  Net::SMTPAuthenticationError")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "renders both the text and HTML parts of the smoke template" do
      described_class.new(to: "skylar@example.com", logger: logger).run

      delivery = ActionMailer::Base.deliveries.last
      expect(delivery.parts.size).to eq(2)
      text_part = delivery.parts.find { |p| p.content_type.start_with?("text/plain") }
      html_part = delivery.parts.find { |p| p.content_type.start_with?("text/html") }
      expect(text_part.body.to_s).to include("BiteWorthy SMTP smoke test")
      expect(html_part.body.to_s).to include("<h1>BiteWorthy SMTP smoke test</h1>")
    end
  end
end
