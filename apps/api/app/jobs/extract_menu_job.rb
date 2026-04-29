# Phase 2.3 — first stage of the AI ingestion pipeline.
#
# Triggered automatically when an IngestionRun transitions into
# `:extracting` (see the JOB_FOR map in IngestionRun). Reads the
# attached input image(s), calls Anthropic vision with the menu
# extraction prompt, validates the response against
# `Ingestion::MENU_EXTRACTION_SCHEMA`, writes the structured output
# to `IngestionRun#staging`, and transitions to `:resolving` (which
# fires Phase 2.4's ResolveIngredientsJob).
#
# Failure modes:
#   * No input attachments → fail!("no_inputs_attached")
#   * AnthropicClient::ApiError → fail!("anthropic_api_error: ...")
#   * AnthropicClient::ValidationError → fail!("schema_validation_failed: ...")
#
# Idempotence: re-running on a run already past `:extracting`
# is a no-op (transition_to! is idempotent).
class ExtractMenuJob < ApplicationJob
  queue_as :ingestion

  def perform(ingestion_run_id)
    run = IngestionRun.find(ingestion_run_id)
    return if run.staged? || run.published? || run.failed?

    # Job dispatch fires when the run enters `:extracting` — being
    # called BEFORE that means we got dispatched manually; flip the
    # state ourselves so the audit trail is right.
    run.transition_to!(:extracting) if run.queued?

    blobs = Array(run.inputs.attached? ? run.inputs.blobs : [])
    if blobs.empty?
      run.fail!("no_inputs_attached")
      return
    end

    client = AnthropicClient.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      result = client.messages_create(
        system:          Ingestion::ExtractMenuPrompt.system(client),
        messages:        Ingestion::ExtractMenuPrompt.user_messages(client, blobs),
        response_schema: Ingestion::MenuExtractionSchema
      )
    rescue AnthropicClient::ApiError => e
      run.fail!("anthropic_api_error: #{e.status} #{e.body.to_s.truncate(500)}")
      return
    rescue AnthropicClient::ValidationError => e
      run.fail!("schema_validation_failed: #{e.errors.first(3).join('; ')}")
      return
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    run.update!(
      staging:    result,
      latency_ms: elapsed_ms
    )
    run.transition_to!(:resolving)
  end
end
