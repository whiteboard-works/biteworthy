# Shared Anthropic-call handling for the ingestion jobs (ExtractMenuJob
# + the ResolveStageJob subclasses).
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
  # Returns `[result, elapsed_ms]`, or `nil` when the call failed and the
  # run was already marked failed (so callers `return if out.nil?`).
  def timed_anthropic_call(run, api_error:, validation_error:)
    client  = AnthropicClient.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      result = yield client
    rescue AnthropicClient::ApiError => e
      run.fail!("#{api_error}: #{e.status} #{e.body.to_s.truncate(500)}")
      return nil
    rescue AnthropicClient::ValidationError => e
      run.record_api_usage!(client.last_usage, model: client.model)
      run.fail!("#{validation_error}: #{e.errors.first(3).join('; ')}")
      return nil
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    run.record_api_usage!(client.last_usage, model: client.model)
    [result, elapsed_ms]
  end
end
