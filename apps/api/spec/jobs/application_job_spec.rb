# frozen_string_literal: true

require "rails_helper"

# Solid Queue files a job's final exception as a failed execution and
# never hands it to `Rails.error` (`ClaimedExecution#execute` rescues it
# inside the app executor), so the job reports it — once, when there
# will be no further attempt.
RSpec.describe ApplicationJob, type: :job do
  include ActiveJob::TestHelper

  before { allow(Rails.error).to receive(:report).and_call_original }
  after { ActiveSupport::ExecutionContext.clear }

  let(:job_class) do
    Class.new(described_class) do
      def self.name = "ExhaustingJob"

      def perform = raise("boom")
    end
  end

  it "reports the failure once the retries are spent, then lets it fail" do
    job = job_class.new
    job.exception_executions = { "[StandardError]" => described_class::RETRY_ATTEMPTS - 1 }

    expect { job.perform_now }.to raise_error(RuntimeError, "boom")

    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(RuntimeError), hash_including(handled: false, source: "application.active_job")).once
  end

  it "reports nothing for an attempt that will be retried" do
    expect { job_class.new.perform_now }.to have_enqueued_job(job_class)

    expect(Rails.error).not_to have_received(:report)
  end

  # Action Mailer's job is not an ApplicationJob and re-raises through
  # its own handler, which never reaches `after_discard`.
  it "reports a mail delivery that failed" do
    expect { ActionMailer::MailDeliveryJob.perform_now("NoSuchMailer", "hello", "deliver_now", args: []) }
      .to raise_error(NameError)

    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(NameError), hash_including(handled: false, source: "application.active_job")).once
  end
end
