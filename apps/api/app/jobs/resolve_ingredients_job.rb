# Phase 2.4 — second stage of the AI ingestion pipeline.
#
# Triggered automatically when an IngestionRun transitions into
# `:resolving` (see JOB_FOR in IngestionRun). Walks every item in
# `run.staging["sections"][*]["items"]`, asks Anthropic to map them
# onto ingredient slugs from the curated catalog, writes the resolved
# + unresolved arrays back into staging.
#
# On success, fires ResolveTagsJob (which finishes the resolve work
# and transitions the run into `:staged`).
#
# Failure modes mirror ExtractMenuJob: ApiError → fail with status,
# ValidationError → fail with the validator's first 3 errors.
class ResolveIngredientsJob < ApplicationJob
  queue_as :ingestion

  def perform(ingestion_run_id)
    run = IngestionRun.find(ingestion_run_id)
    return if run.staged? || run.published? || run.failed?

    items = collect_items(run.staging)
    if items.empty?
      run.fail!("resolve_ingredients: no_items_in_staging")
      return
    end

    client  = AnthropicClient.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      result = client.messages_create(
        system:          Ingestion::ResolveIngredientsPrompt.system(client, Ingestion::CatalogBuilder.ingredients_text),
        messages:        Ingestion::ResolveIngredientsPrompt.user_messages(items),
        response_schema: Ingestion::ResolutionSchema
      )
    rescue AnthropicClient::ApiError => e
      run.fail!("resolve_ingredients_api_error: #{e.status} #{e.body.to_s.truncate(500)}")
      return
    rescue AnthropicClient::ValidationError => e
      run.fail!("resolve_ingredients_validation_failed: #{e.errors.first(3).join('; ')}")
      return
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    run.update!(
      staging:    apply_resolution(run.staging, result, key: :ingredients),
      latency_ms: elapsed_ms
    )

    ResolveTagsJob.perform_later(run.id)
  end

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

  # Mutate a deep copy of staging by zipping the API response back
  # onto each item by index, writing two new keys: `<key>` (resolved)
  # and `unresolved_<key>`.
  def apply_resolution(staging, result, key:)
    new_staging   = JSON.parse(staging.to_json) # deep copy + stringify
    sections      = Array(new_staging["sections"])
    flat_index    = 0
    by_index      = result["items"].index_by { |row| row["index"] }

    sections.each do |section|
      Array(section["items"]).each do |item|
        row = by_index[flat_index]
        if row
          item[key.to_s]                  = row["resolved"]
          item["unresolved_#{key}".to_s]  = row["unresolved"]
        else
          item[key.to_s]                 ||= []
          item["unresolved_#{key}".to_s] ||= []
        end
        flat_index += 1
      end
    end

    new_staging
  end
end
