# frozen_string_literal: true

module Ingestion
  # Stage two: deterministic resolve. No LLM call.
  #
  # Matches every staged dish against the taxonomy already in Postgres,
  # derives allergen/diet tags in code, links re-scanned dishes to the
  # restaurant's existing Items, and lands the run in :staged — seconds,
  # not the tens of seconds extraction takes.
  #
  # Dishes the resolver flags as gaps then get ONE background Haiku call
  # (GapFillResolveJob) that appends AI suggestions to still-pending items.
  # `enrichment_status` tells callers whether that pass is still running. No
  # gaps means the run is fully enriched right here.
  #
  # The body lives here rather than in ResolveItemsJob so the job stays a
  # thin wrapper and the logic is directly callable.
  class ResolveRun
    def self.call(run) = new(run).call

    def initialize(run)
      @run = run
    end

    def call
      return if @run.staged? || @run.published? || @run.failed?

      # Resolves from the item rows themselves rather than by index, so
      # every materialized item participates regardless of how it was created.
      items = @run.ingestion_items.order(:position).to_a
      if items.empty?
        @run.fail!("resolve: no_items")
        return
      end

      results = DeterministicResolver.call(items)
      gaps    = results.any?(&:gap?)
      # Re-scan dedup: link staged items to the restaurant's existing Items
      # before the batch promote below, so items accepted while the run was
      # still :resolving promote as updates instead of duplicates.
      matches = ExistingItemMatcher.call(run: @run, items: items)

      @run.transaction do
        write_payloads!(items, results, matches)
        promote_accepted_items!
        @run.transition_to!(:staged)
        # Written both ways so a re-extract can't inherit a stale value from
        # the previous cycle.
        @run.update!(enrichment_status: gaps ? "pending" : "completed")
        @run.maybe_publish!
      end

      GapFillResolveJob.perform_later(@run.id) if gaps
    end

    private

    # One batched statement instead of an UPDATE per item. Always conflicts
    # on the PK (the ids were just read from the DB), so this is a pure bulk
    # UPDATE; bypassing validations and callbacks is safe — IngestionItem has
    # none that touch these columns.
    def write_payloads!(items, results, matches)
      by_id = items.index_by(&:id)
      # ingestion_run_id rides along because Postgres checks NOT NULL on the
      # insert tuple before ON CONFLICT resolves; updated_at is stamped by
      # upsert_all itself.
      rows = results.map do |r|
        staged = by_id.fetch(r.item_id)
        match  = matches[r.item_id]
        # Already-promoted items keep their linkage; everyone else takes this
        # pass's match — nil clears anything stale from a prior cycle.
        promoted = staged.item_id.present?
        { id: r.item_id,
          ingestion_run_id: @run.id,
          ingredients_payload: r.ingredients,
          tags_payload: r.tags,
          matched_item_id: promoted ? staged.matched_item_id : match&.dig(:item_id),
          match_score:     promoted ? staged.match_score     : match&.dig(:score) }
      end
      IngestionItem.upsert_all(
        rows, update_only: %i[ingredients_payload tags_payload matched_item_id match_score]
      )
    end

    # Items accepted while the run was still :resolving were recorded but not
    # promoted — their payloads were empty then. Now that they're enriched,
    # materialize the real Items. Best-effort per item so one bad promotion
    # can't block the run from reaching :staged; promote! is idempotent.
    def promote_accepted_items!
      @run.ingestion_items.where(decision: "accepted", item_id: nil).find_each do |item|
        item.promote!(decided_by: @run.user)
      rescue StandardError => e
        Rails.logger.error(
          "Ingestion::ResolveRun: promote of pre-accepted IngestionItem##{item.id} failed: " \
          "#{e.class} #{e.message}"
        )
      end
    end
  end
end
