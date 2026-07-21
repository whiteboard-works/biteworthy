# Phase 2.4 — third (final) stage of the AI ingestion pipeline.
#
# Triggered by ResolveIngredientsJob on success. Same shape as the
# ingredient stage (skeleton in ResolveStageJob) but with the tag catalog.
#
# Verify-flow redesign: the items were already materialized up front by
# ExtractMenuJob, so this stage ENRICHES them in place (tags) rather than
# creating them. Once every item carries its ingredient + tag payloads it:
#   1. Promotes any item the user accepted while enrichment was still
#      running (recorded then, but NOT promoted — an Item must never go live
#      without its ingredients/tags).
#   2. Transitions the run to :staged and runs the 80%-accepted publish check
#      (a bulk pre-accept may already have crossed the threshold).
class ResolveTagsJob < ResolveStageJob
  def stage        = "resolve_tags"
  def prompt       = Ingestion::ResolveTagsPrompt
  def catalog_text = Ingestion::CatalogBuilder.tags_text

  def apply_and_advance(run, result, elapsed_ms)
    run.transaction do
      apply_resolution_to_items!(
        run, result,
        resolved_col:   :tags_payload,
        unresolved_col: :unresolved_tags
      )
      run.update!(latency_ms: elapsed_ms)
      promote_accepted_items!(run)
      run.transition_to!(:staged)
      run.maybe_publish!
    end
  end

  private

  # Items accepted while the run was still :resolving were recorded but not
  # promoted (their payloads were empty then). Now that they're enriched,
  # materialize the real Items. decided_by is the run's user, matching the
  # community self-verify trust model (creator → suggested; admin-owned run /
  # no user → confirmed). Best-effort per item so one bad promotion can't
  # block the whole run from reaching :staged; promote! is idempotent.
  def promote_accepted_items!(run)
    run.ingestion_items.where(decision: "accepted", item_id: nil).find_each do |item|
      item.promote!(decided_by: run.user)
    rescue StandardError => e
      Rails.logger.error(
        "ResolveTagsJob: promote of pre-accepted IngestionItem##{item.id} failed: " \
        "#{e.class} #{e.message}"
      )
    end
  end
end
