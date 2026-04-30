# Phase 2.4 — third stage of the AI ingestion pipeline.
#
# Triggered by ResolveIngredientsJob on success. Same shape but with
# the tag catalog instead of the ingredient catalog. After writing
# the tag resolution back to staging, this job:
#
# 1. Materializes IngestionItem rows (one per item in staging) with
#    `decision: pending` so the swipe-verify UI in Phase 2.7 has
#    something to show.
# 2. Transitions the run to `:staged` (Phase 2.5's verify UI takes
#    over from there).
class ResolveTagsJob < ApplicationJob
  queue_as :ingestion

  def perform(ingestion_run_id)
    run = IngestionRun.find(ingestion_run_id)
    return if run.staged? || run.published? || run.failed?

    items = ResolveIngredientsJob.collect_items(run.staging)
    if items.empty?
      run.fail!("resolve_tags: no_items_in_staging")
      return
    end

    client  = AnthropicClient.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      result = client.messages_create(
        system:          Ingestion::ResolveTagsPrompt.system(client, Ingestion::CatalogBuilder.tags_text),
        messages:        Ingestion::ResolveTagsPrompt.user_messages(items),
        response_schema: Ingestion::ResolutionSchema
      )
    rescue AnthropicClient::ApiError => e
      run.fail!("resolve_tags_api_error: #{e.status} #{e.body.to_s.truncate(500)}")
      return
    rescue AnthropicClient::ValidationError => e
      run.fail!("resolve_tags_validation_failed: #{e.errors.first(3).join('; ')}")
      return
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    new_staging = ResolveIngredientsJob.new.apply_resolution(run.staging, result, key: :tags)

    run.transaction do
      run.update!(staging: new_staging, latency_ms: elapsed_ms)
      materialize_ingestion_items!(run)
      run.transition_to!(:staged)
    end
  end

  private

  # Walk the resolved staging payload and create one IngestionItem
  # per extracted item, ready for the swipe-verify UI to operate on.
  def materialize_ingestion_items!(run)
    Array(run.staging["sections"]).each do |section|
      section_name = section["name"]
      Array(section["items"]).each do |item|
        IngestionItem.create!(
          ingestion_run:           run,
          name:                    item["name"],
          description:             item["description"],
          section_name:            section_name,
          prices_payload:          Array(item["prices"]),
          ingredients_payload:     Array(item["ingredients"]),
          tags_payload:            Array(item["tags"]),
          unresolved_ingredients:  Array(item["unresolved_ingredients"]),
          unresolved_tags:         Array(item["unresolved_tags"]),
          # Phase 4.11.2 — bbox is optional in the schema; nil is the
          # signal "no inline photo for this dish." Phase 4.11.3's
          # IngestionItem#promote! reads this column to decide whether
          # to crop + attach.
          image_bbox:              item["image_bbox"],
          decision:                "pending"
        )
      end
    end
  end
end
