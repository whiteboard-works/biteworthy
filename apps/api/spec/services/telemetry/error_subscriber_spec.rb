require "rails_helper"

RSpec.describe Telemetry::ErrorSubscriber do
  let(:error) { RuntimeError.new("mailer down") }

  # posthog-rails' own subscriber skips any report made during a request and
  # leaves it to its middleware, which only sees exceptions that escaped.
  # A controller's `Rails.error.report` escapes nothing, so without this
  # the waitlist's "could not queue the confirmation" would reach no one.
  it "reports a handled error made inside a web request, with its scalar context" do
    PostHog::Rails.enter_web_request
    captured = nil
    allow(PostHog).to receive(:capture_exception) { |*args, **kwargs| captured = [ args, kwargs ] }

    Rails.error.report(error, handled: true, context: { component: :waitlist, attempt: 2, controller: Object.new, user_id: 7 })

    args, kwargs = captured
    expect(args[0]).to be(error)
    expect(args[1]).to be_nil
    expect(args[2]).to include("$exception_source" => "application", "$exception_handled" => true,
                               "$context_component" => "waitlist", "$context_attempt" => 2)
    expect(args[2]).not_to have_key("$context_user_id")
    expect(args[2]).not_to have_key("$context_controller")
    expect(kwargs).to eq(mechanism: { "type" => "rails_error_reporter", "handled" => true })
  ensure
    PostHog::Rails.exit_web_request
  end

  it "leaves reports made outside a request to posthog-rails, so nothing is reported twice" do
    PostHog::Rails.exit_web_request
    allow(PostHog).to receive(:capture_exception)

    described_class.new.report(error, handled: true, severity: :warning, context: {}, source: "application")

    expect(PostHog).not_to have_received(:capture_exception)
  end

  it "never raises into the code that reported" do
    PostHog::Rails.enter_web_request
    allow(PostHog).to receive(:capture_exception).and_raise(IOError, "socket")

    expect { described_class.new.report(error, handled: true, severity: :error, context: {}) }.not_to raise_error
  ensure
    PostHog::Rails.exit_web_request
  end
end
