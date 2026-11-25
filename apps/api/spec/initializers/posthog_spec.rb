require "rails_helper"
require "google/protobuf"

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

  # posthog-rails 3.20 (3cf8079) captures handled Rails.error.report calls
  # made during a web request and removed the private in_web_request helpers
  # Telemetry::ErrorSubscriber used to fill that hole. A second subscriber
  # would race capture_exception's first-wins dedupe.
  it "lets posthog-rails capture handled Rails.error.report, including during a request" do
    subscribers = Rails.error.instance_variable_get(:@subscribers)
    expect(subscribers).to include(an_instance_of(PostHog::Rails::ErrorSubscriber))
    expect(subscribers.map { |s| s.class.name }).not_to include("Telemetry::ErrorSubscriber")

    error = RuntimeError.new("mailer down")
    captured = nil
    allow(PostHog).to receive(:capture_exception) { |*args, **kwargs| captured = [ args, kwargs ] }

    Rails.error.report(error, handled: true, context: { component: :waitlist, attempt: 2, user_id: 7 })

    args, kwargs = captured
    expect(args[0]).to be(error)
    expect(args[2]).to include("$exception_handled" => true, "$context_attempt" => 2)
    expect(kwargs[:mechanism]).to include("type" => "rails_error_reporter", "handled" => true)
  end

  # The gem's ErrorSubscriber always does `context[:user_id] || context[:distinct_id]`
  # as capture_exception's second argument, independent of capture_user_context
  # (that flag only covers the middleware path). Passing those keys through
  # would attach a person to a server error, which ADR 0009 forbids.
  it "does not identify a Rails.error.report from context user_id or distinct_id" do
    expect(PostHog::Rails::ErrorSubscriber.ancestors).to include(Telemetry::AnonymousErrorReports)

    error = RuntimeError.new("mailer down")
    captured = nil
    allow(PostHog).to receive(:capture_exception) { |*args, **kwargs| captured = [ args, kwargs ] }

    Rails.error.report(
      error,
      handled: true,
      context: { component: :waitlist, attempt: 2, user_id: 7, distinct_id: "person-7" }
    )

    args, = captured
    expect(args[0]).to be(error)
    expect(args[1]).to be_nil
    expect(args[2]).to include("$context_attempt" => 2)
    expect(args[2]).not_to have_key("$context_user_id")
    expect(args[2]).not_to have_key("$context_distinct_id")
  end

  it "keeps the diet and the search out of request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter("profile" => "celiac", "strictness" => "strict", "q" => "gluten free", "limit" => "20"))
      .to eq("profile" => "[FILTERED]", "strictness" => "[FILTERED]", "q" => "[FILTERED]", "limit" => "20")
  end

  describe "the OpenTelemetry error handler" do
    let(:otel_logger) { instance_double(Logger) }

    before { allow(OpenTelemetry).to receive(:logger).and_return(otel_logger) }

    it "drops the exporter's complaint about PostHog's JSON acknowledgement of a delivered batch" do
      expect(otel_logger).not_to receive(:error)
      OpenTelemetry.handle_error(
        exception: Google::Protobuf::ParseError.new("Error occurred during parsing"),
        message: "unexpected error decoding ExportLogsServiceResponse in OTLP::Exporter#log_partial_success"
      )
    end

    it "still reports everything else, a rejected record included" do
      expect(otel_logger).to receive(:error).with(a_string_including("rejected_log_records=3"))
      OpenTelemetry.handle_error(message: "OTLP logs exporter received partial success: rejected_log_records=3, error_message=too big")
    end

    it "still reports a response that fails to decode for any other reason" do
      expect(otel_logger).to receive(:error).with(a_string_including("ExportLogsServiceResponse"))
      OpenTelemetry.handle_error(
        exception: IOError.new("closed stream"),
        message: "unexpected error decoding ExportLogsServiceResponse in OTLP::Exporter#log_partial_success"
      )
    end
  end

  it "keeps the test suite offline" do
    expect(PostHog.client.instance_variable_get(:@worker)).to be_a(PostHog::NoopWorker)
  end
end
