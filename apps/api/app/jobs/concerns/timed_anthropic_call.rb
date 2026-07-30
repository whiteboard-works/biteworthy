# Shared Anthropic-call handling for the ingestion jobs (ExtractMenuJob
# + GapFillResolveJob).
#
# Every stage makes one timed `messages_create` and handles failure the
# same way. Centralised here so the cost-accrual invariant lives in ONE
# place: a 200 that fails our schema was still billed, so its usage must
# be recorded even though the run fails — otherwise a run could leak past
# the daily cost ceiling by failing validation.
module TimedAnthropicCall
  extend ActiveSupport::Concern

  private

  # Yields a fresh AnthropicClient so the caller can build + send its
  # prompt, times the call, and applies the shared failure handling.
  # Records the API usage on success AND on a validation failure (both
  # were billed). The `*_error` labels keep each stage's failure-message
  # prefix.
  #
  # Returns `[result, elapsed_ms]`, or `nil` when the call failed (so
  # callers `return if out.nil?`). With the default `fail_run: true` the
  # run is marked failed; `fail_run: false` (the post-staged gap-fill —
  # the run is already usable) logs instead, leaving the caller to
  # record the degradation (e.g. enrichment_status).
  def timed_anthropic_call(run, api_error:, validation_error:, model: nil, fail_run: true)
    client  = AnthropicClient.new(model: model)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      result = yield client
    rescue AnthropicClient::ApiError => e
      message = "#{api_error}: #{e.status} #{e.body.to_s.truncate(500)}"
      fail_run ? run.fail!(message) : log_soft_failure(run, message)
      return nil
    rescue AnthropicClient::ValidationError => e
      run.record_api_usage!(client.last_usage, model: client.model)
      message = "#{validation_error}: #{e.errors.first(3).join('; ')}"
      fail_run ? run.fail!(message) : log_soft_failure(run, message)
      return nil
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    run.record_api_usage!(client.last_usage, model: client.model)
    [result, elapsed_ms]
  end

  def log_soft_failure(run, message)
    Rails.logger.error("#{self.class.name}: IngestionRun##{run.id} #{message}")
  end
end

