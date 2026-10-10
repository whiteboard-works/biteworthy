require "rails_helper"

# Pins the privacy posture of the PostHog initializer: server errors are
# reported, and nothing ties one to a person. A future "just turn on user
# context" has to come through here.
RSpec.describe "config/initializers/posthog.rb" do
  let(:config) { PostHog::Rails.config }

  it "reports unhandled and explicitly reported exceptions, not rescued ones" do
    expect(config.auto_capture_exceptions).to be(true)
    expect(config.report_rescued_exceptions).to be(false)
    expect(config.auto_instrument_active_job).to be(false)
  end

  it "attaches no identity to a server error" do
    expect(config.capture_user_context).to be(false)
    expect(config.use_tracing_headers).to be(false)
  end

  it "forwards logs at info and above through the scrubber" do
    expect(config.logs_enabled).to be(true)
    expect(config.logs_level).to eq(:info)
    record = config.logs_before_send.call({ body: "for 203.0.113.9 at 2026-10-10", attributes: {} })
    expect(record[:body]).to eq("for <ip> at 2026-10-10")
  end

  it "is subscribed to Rails.error twice: outside a request (posthog-rails) and inside one (ours)" do
    subscribers = Rails.error.instance_variable_get(:@subscribers)
    expect(subscribers).to include(an_instance_of(PostHog::Rails::ErrorSubscriber))
    expect(subscribers).to include(an_instance_of(Telemetry::ErrorSubscriber))
  end

  it "keeps the diet and the search out of request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter("profile" => "celiac", "strictness" => "strict", "q" => "gluten free", "limit" => "20"))
      .to eq("profile" => "[FILTERED]", "strictness" => "[FILTERED]", "q" => "[FILTERED]", "limit" => "20")
  end

  it "keeps the test suite offline" do
    expect(PostHog.client.instance_variable_get(:@worker)).to be_a(PostHog::NoopWorker)
  end
end
