# Phase 2.3 — first stage of the AI ingestion pipeline.
#
# Triggered automatically when an IngestionRun transitions into
# `:extracting` (see the JOB_FOR map in IngestionRun). Reads the
# attached input image(s), calls Anthropic vision with the menu
# extraction prompt, validates the response against
# `Ingestion::MENU_EXTRACTION_SCHEMA`, writes the structured output
# to `IngestionRun#staging`, and transitions to `:resolving` (which
# fires the deterministic ResolveItemsJob).
#
# Failure modes:
#   * No input attachments → fail!("no_inputs_attached")
#   * AnthropicClient::ApiError → fail!("anthropic_api_error: ...")
#   * AnthropicClient::ValidationError → fail!("schema_validation_failed: ...")
#
# Idempotence: re-running on a run already past `:extracting`
# is a no-op (transition_to! is idempotent).
class ExtractMenuJob < ApplicationJob
  include TimedAnthropicCall

  queue_as :ingestion

  def perform(ingestion_run_id)
    run = IngestionRun.find(ingestion_run_id)
    return if run.resolving? || run.staged? || run.published? || run.failed?

    # Job dispatch fires when the run enters `:extracting` — being
    # called BEFORE that means we got dispatched manually; flip the
    # state ourselves so the audit trail is right.
    run.transition_to!(:extracting) if run.queued?

    blobs = Array(run.inputs.attached? ? run.inputs.blobs : [])
    if blobs.empty?
      run.fail!("no_inputs_attached")
      return
    end

    out = timed_anthropic_call(run, api_error: "anthropic_api_error", validation_error: "schema_validation_failed") do |client|
      client.messages_create(
        system:          Ingestion::ExtractMenuPrompt.system(client),
        messages:        Ingestion::ExtractMenuPrompt.user_messages(client, blobs),
        response_schema: Ingestion::MenuExtractionSchema
      )
    end
    return if out.nil?
    result, elapsed_ms = out

    # Verify-flow redesign: materialize the dishes NOW (empty ingredient/tag
    # payloads) so the verify page shows them immediately, then transition to
    # :resolving where the resolve stages enrich each item in the background.
    # Atomic with the transition so a run never sits in :resolving without its
    # items. Guarded above (return if resolving?) against a re-run.
    run.transaction do
      run.update!(staging: result, latency_ms: elapsed_ms)
      materialize_items!(run)
      run.transition_to!(:resolving)
    end
  end

  private

  # One IngestionItem per extracted item, in flat order, carrying the
  # position so the resolve stages can write their indexed results back onto
  # the right row. ingredients_payload / tags_payload stay empty ([] default)
  # until enrichment fills them.
  #
  # Add-on guard: the extraction prompt nests add-on/upsell lines under
  # their parent dish (`addons`), but the model sometimes still emits an
  # "Add X" line as a top-level item. Those fold into the PREVIOUS item's
  # addons_payload here (source: "guard") instead of materializing — an
  # upsell line must never publish as a dish. First-in-section has no
  # parent to attach to, so it materializes normally.
  def materialize_items!(run)
    position = 0
    Array(run.staging["sections"]).each do |section|
      previous = nil
      Array(section["items"]).each do |item|
        if previous && addon_line?(item["name"])
          previous.update!(addons_payload: previous.addons_payload + [guard_addon_row(item)])
          next
        end

        previous = run.ingestion_items.create!(
          name:           item["name"],
          description:    item["description"],
          section_name:   section["name"],
          prices_payload: Array(item["prices"]),
          addons_payload: addon_rows(item["addons"]),
          image_bbox:     item["image_bbox"],
          position:       position,
          decision:       "pending"
        )
        position += 1
      end
    end
  end

  # Deliberately narrow — a false fold silently drops a dish with no
  # recovery path in verify, so only the unambiguous "Add …" prefix
  # triggers. Not "extra" (collides with "Extra Crispy Wings") and not
  # a trailing "+" (menus use it as a footnote/spice marker); those rely
  # on the prompt's LLM classification, and a miss just stages a card a
  # human can reject.
  def addon_line?(name)
    name.to_s.strip.match?(/\Aadd\s/i)
  end

  def addon_rows(addons)
    Array(addons).map do |addon|
      { "name" => addon["name"], "price_cents" => addon["price_cents"], "source" => "extract" }
    end
  end

  def guard_addon_row(item)
    name = item["name"].to_s.strip.sub(/\Aadd\s+/i, "").sub(/\s*\+\z/, "").strip
    first_price = Array(item["prices"]).first || {}
    { "name" => name, "price_cents" => first_price["price_cents"], "source" => "guard" }
  end
end
