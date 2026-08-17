# Background LLM enrichment pass, enqueued by ResolveItemsJob after the
# run is already :staged and usable. Haiku calls covering only the items
# the deterministic resolver flagged as gaps (one call per slice of 25 —
# the composed-dish trigger can flag most of a menu), asking only for
# what code can't derive: implied ingredients + cuisine tags.
#
# Contract:
#   * Append-only for ingredients — never removes or rewrites a
#     deterministic match; unknown slugs from the model are dropped.
#   * Only touches items still `decision: "pending"` (row-locked, so a
#     concurrent accept wins and the item is skipped).
#   * Tags are fully re-derived in code over the merged ingredient set —
#     allergen/diet/prep/flavor are NEVER taken from the model. Safe to
#     rebuild because every tag row on a pending item is machine-authored.
#   * Failure never fails the run — it's already staged; we record
#     `enrichment_status: "failed"` and the verify flow continues on
#     deterministic data.
class GapFillResolveJob < ApplicationJob
  include TimedAnthropicCall

  queue_as :ingestion

  # Same cheap-model override knob the old resolve stages had.
  DEFAULT_RESOLVE_MODEL = "claude-haiku-4-5-20251001"

  # Items per API call. Keeps each response inside the output-token
  # budget now that composed-dish names widen the gap set well past
  # "nothing matched".
  GAP_BATCH_SIZE = 25

  # One slice's API call soft-failed (timed_anthropic_call already
  # logged it and recorded any billed usage). Raised so the rescue below
  # records the degradation and retry_on drives a re-run — replays are
  # safe because the retry recomputes the gap set and merge! dedupes by
  # slug, skipping rows already landed.
  SliceFailedError = Class.new(StandardError)

  def resolve_model = ENV.fetch("INGESTION_RESOLVE_MODEL", DEFAULT_RESOLVE_MODEL)

  def perform(ingestion_run_id)
    run = IngestionRun.find(ingestion_run_id)
    return if run.failed? || run.enrichment_status == "completed"
    return unless run.staged? || run.published?

    gaps = gap_rows(run)
    if gaps.empty?
      run.update!(enrichment_status: "completed")
      return
    end

    ingredient_paths = Ingredient.pluck(:slug, :path).to_h
    cuisine_slugs    = Tag.where(family: "cuisine").pluck(:slug).to_set

    # One call per slice; each slice merges before the next call, so the
    # enrichment already landed survives a later slice's failure. The
    # usage accounting stays per-call: timed_anthropic_call records each
    # client's billed tokens itself.
    gaps.each_slice(GAP_BATCH_SIZE) do |slice|
      out = timed_anthropic_call(
        run,
        api_error:        "gap_fill_api_error",
        validation_error: "gap_fill_validation_failed",
        model:            resolve_model,
        fail_run:         false
      ) do |client|
        client.messages_create(
          system:          Ingestion::GapFillPrompt.system(client),
          messages:        Ingestion::GapFillPrompt.user_messages(slice.map { |g| g[:prompt_row] }),
          response_schema: Ingestion::GapFillSchema
        )
      end
      raise SliceFailedError, "gap-fill slice failed (see log for the cause)" if out.nil?

      result, = out
      merge!(run, slice, result, ingredient_paths, cuisine_slugs)
    end
    run.update!(enrichment_status: "completed")
  rescue StandardError
    # Everything that should reach retry_on (a slice's SliceFailedError,
    # transport errors that bypass ApiError, DB hiccups, bugs): record
    # the degradation so clients stop polling, then re-raise so retry_on
    # gets its attempts — a successful retry flips this back to
    # completed.
    run&.update_columns(enrichment_status: "failed", updated_at: Time.current) if run&.persisted?
    raise
  end

  private

  # Recompute the gap set from scratch (the resolver is stateless and
  # cheap) instead of trusting anything persisted at stage time — items
  # accepted/edited since then drop out via the pending filter.
  def gap_rows(run)
    items   = run.ingestion_items.where(decision: "pending").order(:position).to_a
    results = Ingestion::DeterministicResolver.call(items)

    items.zip(results).filter_map do |item, res|
      next unless res.gap?

      { item_id: item.id,
        prompt_row: {
          name:        item.name,
          description: item.description,
          section:     item.section_name,
          matched:     Array(item.ingredients_payload).map { |r| r["slug"] },
          unmatched:   res.gap_phrases
        } }
    end
  end

  def merge!(run, gaps, result, ingredient_paths, cuisine_slugs)
    response_by_index = Array(result["items"]).each_with_object({}) { |row, h| h[row["index"]] ||= row }

    run.transaction do
      # order(:id) keeps lock acquisition in PK order, matching
      # accept_all's find_each — inconsistent ordering could deadlock.
      locked = run.ingestion_items
                  .where(id: gaps.map { |g| g[:item_id] }, decision: "pending")
                  .order(:id).lock.index_by(&:id)

      rows = gaps.each_with_index.filter_map do |gap, index|
        item     = locked[gap[:item_id]]
        response = response_by_index[index]
        next if item.nil? || response.nil?

        merged = merge_ingredients(item, response.dig("ingredients", "resolved"), ingredient_paths)
        # ingestion_run_id: Postgres checks NOT NULL on the insert tuple
        # before ON CONFLICT resolves.
        { id:                     item.id,
          ingestion_run_id:       run.id,
          ingredients_payload:    merged,
          tags_payload:           rebuild_tags(item, merged, response.dig("cuisine_tags", "resolved"),
                                               ingredient_paths, cuisine_slugs),
          unresolved_ingredients: Array(response.dig("ingredients", "unresolved")),
          unresolved_tags:        Array(response.dig("cuisine_tags", "unresolved")) }
      end

      if rows.any?
        # upsert_all stamps updated_at itself (record_timestamps).
        IngestionItem.upsert_all(
          rows,
          update_only: %i[ingredients_payload tags_payload unresolved_ingredients unresolved_tags]
        )
      end
    end
  end

  def merge_ingredients(item, ai_rows, ingredient_paths)
    merged = Array(item.ingredients_payload).dup
    known  = merged.map { |r| r["slug"] }.to_set

    Array(ai_rows).each do |row|
      slug = row["slug"]
      next if known.include?(slug)

      unless ingredient_paths.key?(slug)
        Rails.logger.warn("GapFillResolveJob: dropping unknown ingredient slug #{slug.inspect}")
        next
      end

      merged << Ingestion::AssociationPayload.dump(slug: slug, confidence: row["confidence"], source: "ai")
      known << slug
    end
    merged
  end

  # Machine provenance values. Anything else (no source at all, or a
  # future "human") is a human-authored row and must survive rebuilds —
  # Undo returns an edited item to `pending` WITHOUT resetting payloads,
  # so a pending item can carry human tags (e.g. an added allergen).
  MACHINE_SOURCES = %w[match derived ai].freeze

  def rebuild_tags(item, merged_ingredients, ai_cuisine_rows, ingredient_paths, cuisine_slugs)
    resolved = merged_ingredients.map do |r|
      { slug: r["slug"], path: ingredient_paths[r["slug"]].to_s,
        confidence: r["confidence"], source: r["source"] }
    end

    tags = Array(item.tags_payload).reject { |r| MACHINE_SOURCES.include?(r["source"]) }
    known = tags.map { |t| t["slug"] }.to_set

    Ingestion::TagDeriver.derive(
      segments:             Ingestion::MenuText.segments(item.name, item.description),
      section_segments:     Ingestion::MenuText.segments(item.section_name),
      resolved_ingredients: resolved
    ).each do |t|
      next if known.include?(t[:slug])

      tags << Ingestion::AssociationPayload.load(t).dump
      known << t[:slug]
    end
    Array(ai_cuisine_rows).each do |row|
      slug = row["slug"]
      next if known.include?(slug)

      unless cuisine_slugs.include?(slug)
        Rails.logger.warn("GapFillResolveJob: dropping unknown cuisine tag slug #{slug.inspect}")
        next
      end

      tags << Ingestion::AssociationPayload.dump(slug: slug, confidence: row["confidence"], source: "ai")
      known << slug
    end
    tags
  end
end
