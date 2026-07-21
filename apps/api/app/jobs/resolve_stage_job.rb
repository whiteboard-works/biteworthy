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

  # Mutate a deep copy of staging by zipping the API response back onto
  # each item by index, writing two new keys: `<key>` (resolved) and
  # `unresolved_<key>`.
  def apply_resolution(staging, result, key:)
    new_staging = JSON.parse(staging.to_json) # deep copy + stringify
    flat_index  = 0
    by_index    = result["items"].index_by { |row| row["index"] }

    Array(new_staging["sections"]).each do |section|
      Array(section["items"]).each do |item|
        row = by_index[flat_index]
        if row
          item[key.to_s]            = row["resolved"]
          item["unresolved_#{key}"] = row["unresolved"]
        else
          item[key.to_s]            ||= []
          item["unresolved_#{key}"] ||= []
        end
        flat_index += 1
      end
    end

    new_staging
  end
end
