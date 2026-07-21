# Phase 2.4 — shared skeleton for the two AI "resolve" stages of the
# ingestion pipeline (ResolveIngredientsJob → ResolveTagsJob).
#
# Both stages do the same thing: load the run, ask Anthropic to map the
# staged items onto a curated catalog (ingredients or tags), record the
# API usage + latency, and write the resolution back into staging. They
# differ only in the prompt + catalog, the stage name (used in failure
# messages and as the resolution key), and what happens after a
# successful resolve. Subclasses supply those via the hooks below.
#
# Failure modes: ApiError → fail with status; ValidationError → still
# accrue the (billed) cost, then fail with the validator's first 3
# errors.
class ResolveStageJob < ApplicationJob
  include TimedAnthropicCall

  queue_as :ingestion

  def perform(ingestion_run_id)
    run = IngestionRun.find(ingestion_run_id)
    return if run.staged? || run.published? || run.failed?

    items = collect_items(run.staging)
    if items.empty?
      run.fail!("#{stage}: no_items_in_staging")
      return
    end

    out = timed_anthropic_call(
      run,
      api_error:        "#{stage}_api_error",
      validation_error: "#{stage}_validation_failed",
      model:            resolve_model
    ) do |client|
      client.messages_create(
        system:          prompt.system(client, catalog_text),
        messages:        prompt.user_messages(items),
        response_schema: Ingestion::ResolutionSchema
      )
    end
    return if out.nil?
    result, elapsed_ms = out

    apply_and_advance(run, result, elapsed_ms)
  end

  # ── Subclass hooks ────────────────────────────────────────────────

  # Short stage name, used in failure messages (e.g. "resolve_tags").
  def stage = raise(NotImplementedError)

  # The Ingestion::Resolve*Prompt module for this stage.
  def prompt = raise(NotImplementedError)

  # The curated catalog text the prompt is primed with.
  def catalog_text = raise(NotImplementedError)

  # Resolve is catalog slug-mapping, not deep reasoning, so it runs on a
  # faster/cheaper model than extraction's vision call — the dominant
  # cut to the "Matching ingredients…" wait. Overridable per-env for
  # tuning/rollback without a redeploy.
  DEFAULT_RESOLVE_MODEL = "claude-haiku-4-5-20251001"

  def resolve_model = ENV.fetch("INGESTION_RESOLVE_MODEL", DEFAULT_RESOLVE_MODEL)

  # Persist a successful resolution and advance the pipeline. Receives
  # the run, the API result, and the elapsed milliseconds.
  def apply_and_advance(_run, _result, _elapsed_ms) = raise(NotImplementedError)

  # ── Shared staging helpers ────────────────────────────────────────

  # Flatten the section→items tree into a flat array; each entry
  # carries its parent section name for the prompt context.
  def self.collect_items(staging)
    Array(staging["sections"] || staging[:sections]).flat_map do |section|
      section_name = section["name"] || section[:name]
      Array(section["items"] || section[:items]).map do |item|
        { name: item["name"] || item[:name],
          description: item["description"] || item[:description],
          section: section_name }
      end
    end
  end

  def collect_items(staging) = self.class.collect_items(staging)

  # Verify-flow redesign: enrich the IngestionItems (materialized up front by
  # ExtractMenuJob) in place — write this stage's resolution onto each item by
  # `position`. The items, not staging, are now the source of truth the verify
  # UI + promote! read. `collect_items(staging)` (flat order) and the item
  # positions were both assigned in the same section→item order, so the model's
  # row index maps straight to `item.position`. An item whose index the model
  # didn't return keeps its empty defaults.
  def apply_resolution_to_items!(run, result, resolved_col:, unresolved_col:)
    by_index = Array(result["items"]).index_by { |row| row["index"] }

    run.ingestion_items.where.not(position: nil).find_each do |item|
      row = by_index[item.position]
      next unless row

      item.update!(
        resolved_col   => Array(row["resolved"]),
        unresolved_col => Array(row["unresolved"])
      )
    end
  end
end
