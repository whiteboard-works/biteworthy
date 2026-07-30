# Deterministic resolve stage — replaces the two LLM resolve calls
# (ResolveIngredients/ResolveTags) with in-process matching against the
# taxonomy already in Postgres. Triggered when a run enters :resolving
# (JOB_FOR in IngestionRun).
#
# The run reaches :staged as soon as this finishes — seconds, not the
# ~40s the LLM stages took — so the verify UI gets populated items
# immediately. Items the resolver flags as gaps (nothing matched,
# unknown phrases, composite condiments) then get ONE background Haiku
# call (GapFillResolveJob) that appends AI suggestions to still-pending
# items; `enrichment_status` tells clients whether that pass is still
# running. No gaps → the run is fully enriched right here.
class ResolveItemsJob < ApplicationJob
  queue_as :ingestion

  def perform(ingestion_run_id)
    run = IngestionRun.find(ingestion_run_id)
    return if run.staged? || run.published? || run.failed?

    # No position filter: unlike the old index-mapped LLM stages, this
    # resolves from the item rows themselves, so every materialized item
    # participates regardless of how it was created.
    items = run.ingestion_items.order(:position).to_a
    if items.empty?
      run.fail!("resolve: no_items")
      return
    end

    results = Ingestion::DeterministicResolver.call(items)
    gaps = results.any?(&:gap?)

    run.transaction do
      write_payloads!(run, results)
      promote_accepted_items!(run)
      run.transition_to!(:staged)
      run.update!(enrichment_status: "completed") unless gaps
      run.maybe_publish!
    end

    GapFillResolveJob.perform_later(run.id) if gaps
  end

  private

  # One batched statement instead of an UPDATE per item. Always
  # conflicts on the PK (the ids were just read from the DB), so this is
  # a pure bulk UPDATE; bypassing validations/callbacks is safe —
  # IngestionItem has none that touch these columns.
  def write_payloads!(run, results)
    # ingestion_run_id rides along because Postgres checks NOT NULL on
    # the insert tuple before ON CONFLICT resolves; updated_at is
    # stamped by upsert_all itself (record_timestamps).
    rows = results.map do |r|
      { id: r.item_id,
        ingestion_run_id: run.id,
        ingredients_payload: r.ingredients,
        tags_payload: r.tags }
    end
    IngestionItem.upsert_all(rows, update_only: %i[ingredients_payload tags_payload])
  end

  # Items accepted while the run was still :resolving were recorded but
  # not promoted (their payloads were empty then). Now that they're
  # enriched, materialize the real Items. decided_by is the run's user,
  # matching the community self-verify trust model. Best-effort per item
  # so one bad promotion can't block the run from reaching :staged;
  # promote! is idempotent.
  def promote_accepted_items!(run)
    run.ingestion_items.where(decision: "accepted", item_id: nil).find_each do |item|
      item.promote!(decided_by: run.user)
    rescue StandardError => e
      Rails.logger.error(
        "ResolveItemsJob: promote of pre-accepted IngestionItem##{item.id} failed: " \
        "#{e.class} #{e.message}"
      )
    end
  end
end
