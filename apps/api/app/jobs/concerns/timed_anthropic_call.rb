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
  #
  # When `fail_run: false`, also returns the error message as a third
  # element: `[nil, nil, error_msg]`, so the caller can record it.
  def timed_anthropic_call(run, api_error:, validation_error:, truncation_error: "output_truncated",
                           model: nil, fail_run: true)
    client  = AnthropicClient.new(model: model)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      result = yield client
    rescue AnthropicClient::ApiError => e
      # ApiError includes rate limits (429), server errors (5xx), and client
      # errors (4xx). The Faraday retry middleware already retried transient
      # ones, so if we're here it's either persistent or a non-retriable error.
      message = "#{api_error}: #{e.status} #{e.body.to_s.truncate(500)}"
      if fail_run
        run.fail!(message)
        return nil
      else
        log_soft_failure(run, message)
        return [nil, nil, message]
      end
    rescue AnthropicClient::TruncatedError => e
      # Its own failure code, not `#{validation_error}`. A truncated
      # response is a parse failure too, so it used to be reported as
      # malformed model output — which reads as "the prompt is wrong"
      # when the fix is a bigger budget or a smaller batch. The call was
      # billed, so the usage still lands.
      #
      # The label is a keyword like its two neighbours, and for the same
      # reason: this concern serves extraction *and* gap-fill, and a
      # hardcoded "the menu is too large to extract" on a taxonomy
      # resolution failure would be exactly the misleading diagnosis this
      # rescue exists to stop producing.
      run.record_api_usage!(client.last_usage, model: client.model)
      message = "#{truncation_error}: hit the #{e.max_tokens}-token output limit"
      if fail_run
        run.fail!(message)
        return nil
      else
        log_soft_failure(run, message)
        return [nil, nil, message]
      end
    rescue AnthropicClient::ValidationError => e
      run.record_api_usage!(client.last_usage, model: client.model)
      message = "#{validation_error}: #{e.errors.first(3).join('; ')}"
      if fail_run
        run.fail!(message)
        return nil
      else
        log_soft_failure(run, message)
        return [nil, nil, message]
      end
    rescue Faraday::TimeoutError => e
      # Timeout after Faraday's configured timeout (default 240s for Anthropic).
      # This is distinct from Anthropic returning a 408 or 504, which would be
      # caught as ApiError above. A timeout here means the socket read hung.
      timeout_val = client.instance_variable_get(:@timeout) || 240
      message = "#{api_error}: timeout after #{timeout_val}s"
      if fail_run
        run.fail!(message)
        return nil
      else
        log_soft_failure(run, message)
        return [nil, nil, message]
      end
    rescue Faraday::ConnectionFailed, Faraday::SSLError, Errno::ECONNREFUSED => e
      # Network-level failures: DNS failure, connection refused, SSL errors.
      # These are transient and the job's retry_on will handle them.
      message = "#{api_error}: network error - #{e.class.name}: #{e.message.truncate(200)}"
      if fail_run
        run.fail!(message)
        return nil
      else
        log_soft_failure(run, message)
        return [nil, nil, message]
      end
    rescue JSON::ParserError => e
      # JSON parse failure on the response body. This shouldn't happen with
      # the JSON response middleware, but if it does it's a malformed response.
      message = "#{api_error}: failed to parse JSON response - #{e.message.truncate(200)}"
      if fail_run
        run.fail!(message)
        return nil
      else
        log_soft_failure(run, message)
        return [nil, nil, message]
      end
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    run.record_api_usage!(client.last_usage, model: client.model)
    [result, elapsed_ms]
  end

  def log_soft_failure(run, message)
    Rails.logger.error("#{self.class.name}: IngestionRun##{run.id} #{message}")
  end
end

