# Background LLM enrichment pass, enqueued by ResolveItemsJob after the
# run is already :staged and usable. Haiku calls covering only the items
# the deterministic resolver flagged as gaps (one call per slice of 10 —
# the composed-dish trigger can flag most of a menu), asking only for
# what code can't derive: implied ingredients. Each slice then goes to
# Jev (Ingestion::JevCuisineTagger) for its cuisine tags.
#
# Contract:
#   * Append-only for ingredients — never removes or rewrites a
#     deterministic match; unknown slugs from the model are dropped.
#   * Only touches items still `decision: "pending"` (row-locked, so a
#     concurrent accept wins and the item is skipped).
#   * Tags are fully re-derived in code over the merged ingredient set —
#     allergen/diet/prep/flavor are NEVER taken from a model, and cuisine
#     comes only from Jev. Safe to rebuild because every tag row on a
#     pending item is machine-authored.
#   * Failure never fails the run — it's already staged; we record
#     `enrichment_status: "failed"` and the verify flow continues on
#     deterministic data.
class GapFillResolveJob < ApplicationJob
  include TimedAnthropicCall

  queue_as :ingestion

  # Same cheap-model override knob the old resolve stages had.
  DEFAULT_RESOLVE_MODEL = "claude-haiku-4-5-20251001"

  # Items per API call. Reduced from 25 → 15 → 10 to avoid hitting output-token
  # limits or timeouts on large slices. Each item in the batch increases
  # both input (name + description + matched ingredients) and output (resolved
  # ingredients + tags). College Cafe (77 items) failed enrichment at 15/batch;
  # 10/batch keeps slices under ~6K output tokens.
  GAP_BATCH_SIZE = 10

  # Explicit output budget for gap-fill. Each item can emit ~10 ingredients,
  # each with slug + confidence, plus the unresolved array.
  # At 10 items/batch, ~500-600 tokens/item = ~6K tokens, with headroom.
  GAP_MAX_TOKENS = 8_000

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
      # Only a first pass (still pending) may conclude "fully enriched".
      # On a retry after a failure an empty gap set just means the gap
      # items got decided in the meantime — don't launder "failed" into
      # "completed".
      run.update!(enrichment_status: "completed") if run.enrichment_status == "pending"
      return
    end

    ingredient_paths = Ingredient.pluck(:slug, :path).to_h
    tagger           = cuisine_tagger(run)
    wheat_shadow     = Ingestion::JevHiddenWheatShadow.new if Ingestion::JevHiddenWheatShadow.enabled?
    # Dishes an earlier attempt already observed, by id: a retry re-sends
    # a slice whole, and a dish Haiku found nothing for stays "not
    # enriched" forever, so identity is the only honest dedupe.
    observed         = wheat_shadow ? Ingestion::JevHiddenWheatShadow.observed_item_ids(run) : Set.new

    # One call per slice; each slice merges before the next call, so the
    # enrichment already landed survives a later slice's failure. The
    # usage accounting stays per-call: timed_anthropic_call records each
    # client's billed tokens itself.
    gaps.each_slice(GAP_BATCH_SIZE) do |slice|
      prompt_rows = slice.map { |g| g[:prompt_row] }
      result      = nil
      # Retry cheaply: a slice whose every item already carries an AI
      # row was merged by a previous attempt — re-sending it would
      # re-bill for rows merge! deduplicates anyway. Jev is still asked
      # below: it is ~150ms and the previous attempt's Jev call may be
      # the thing that failed.
      unless slice.all? { |g| g[:enriched] }
        out = timed_anthropic_call(
        run,
        api_error:        "gap_fill_api_error",
        validation_error: "gap_fill_validation_failed",
        truncation_error: "gap_fill_truncated",
        model:            resolve_model,
        fail_run:         false
        ) do |client|
          client.messages_create(
            system:          Ingestion::GapFillPrompt.system(client),
            messages:        Ingestion::GapFillPrompt.user_messages(prompt_rows),
            max_tokens:      GAP_MAX_TOKENS,
            response_schema: Ingestion::GapFillSchema
          )
        end

        # When fail_run: false, timed_anthropic_call returns [nil, nil, error_msg] on failure
        if out.nil? || (out.is_a?(Array) && out[0].nil?)
          error_msg = out.is_a?(Array) && out.size == 3 ? out[2] : "gap-fill slice failed"
          # Log the full error for debugging enrichment failures
          Rails.logger.error("GapFillResolveJob failed for run #{run.id}: #{error_msg}")
          run.update(enrichment_failure_message: error_msg) if run.enrichment_failure_message.nil?
          raise SliceFailedError, error_msg
        end

        result, = out
      end

      # Jev never raises: a failure (nil) merges the slice with whatever
      # cuisine rows it already had rather than re-running a Haiku call
      # that succeeded, and switches Jev off for the rest of this attempt
      # so an outage costs one timeout, not one per slice. The next
      # attempt, if there is one, asks again.
      cuisine = tagger&.call(run, prompt_rows, context: { attempt: executions })
      tagger  = nil if cuisine.nil?
      merged  = merge!(run, slice, result, ingredient_paths, cuisine)
      # Observation only, after the merge so it measures what landed, and
      # only for dishes no earlier attempt observed, so none is counted
      # twice while a slice whose first attempt failed before the merge
      # still gets its observation when a retry lands it. A shadow that
      # fails writes a failed observation and nothing else, and is not
      # asked again this attempt so an outage costs one timeout.
      # Whether a dish needs observing is answered by the persisted ids
      # alone, not by whether Haiku ran this attempt: a worker interrupted
      # between the merge's commit and the shadow call leaves a slice
      # fully enriched and wholly unobserved, and the retry must still
      # observe it from the rows the merge already landed.
      if wheat_shadow
        fresh = slice.each_index.reject { |i| observed.include?(slice[i][:item_id]) }
        unless fresh.empty?
          rows   = fresh.map { |i| prompt_rows[i] }
          landed = fresh.each_with_index.to_h { |orig, i| [ i, merged[orig] ] }.compact
          ids    = fresh.map { |i| slice[i][:item_id] }
          if wheat_shadow.call(run, rows, landed, ingredient_paths, attempt: executions, item_ids: ids)
            observed.merge(ids)
          else
            wheat_shadow = nil
          end
        end
      end
    end
    run.update!(enrichment_status: "completed", enrichment_failure_message: nil)
  rescue StandardError => e
    # Everything that should reach retry_on (a slice's SliceFailedError,
    # transport errors that bypass ApiError, DB hiccups, bugs) re-raises so
    # retry_on gets its attempts. Only the LAST attempt records the
    # degradation: `failed` is what tells clients to stop waiting, and an
    # earlier stamp told them to give up on a pass a retry then finished.
    # The stamp is conditional on still-pending so a stale attempt can
    # never demote an enrichment already completed.
    if run&.persisted? && executions >= RETRY_ATTEMPTS
      # Capture detailed error info for admin visibility
      error_summary = "#{e.class.name}: #{e.message}"
      Rails.logger.error("GapFillResolveJob final failure for run #{run.id}: #{error_summary}")

      IngestionRun.where(id: run.id, enrichment_status: "pending")
                  .update_all(
                    enrichment_status: "failed",
                    enrichment_failure_message: error_summary.truncate(2_000),
                    updated_at: Time.current
                  )
    end
    raise
  end

  private

  # Jev is the only source of AI cuisine tags; without a key the family
  # degrades to TagDeriver's keyword pass, warned on every attempt that
  # enriches, rather than falling back to asking Haiku.
  def cuisine_tagger(run)
    return Ingestion::JevCuisineTagger.new if Ingestion::JevCuisineTagger.enabled?

    Rails.logger.warn("[jev_cuisine] JEV_API_KEY unset: IngestionRun##{run.id} gets keyword cuisine tags only")
    nil
  end

  # Recompute the gap set from scratch (the resolver is stateless and
  # cheap) instead of trusting anything persisted at stage time — items
  # accepted/edited since then drop out via the pending filter.
  def gap_rows(run)
    items   = run.ingestion_items.where(decision: "pending").order(:position).to_a
    results = Ingestion::DeterministicResolver.call(items)

    items.zip(results).filter_map do |item, res|
      next unless res.gap?

      { item_id: item.id,
        enriched: Array(item.ingredients_payload).any? { |r| r["source"] == "ai" },
        prompt_row: {
          name:        item.name,
          description: item.description,
          section:     item.section_name,
          matched:     Array(item.ingredients_payload).map { |r| r["slug"] },
          unmatched:   res.gap_phrases
        } }
    end
  end

  # `result` is Haiku's parsed response, or nil when the slice was
  # already enriched and only Jev was asked. `cuisine` is
  # JevCuisineTagger's { index => rows } for this slice, or nil when Jev
  # could not answer (existing AI cuisine rows then stay as they are).
  # Returns { index => merged ingredient rows } for the wheat shadow.
  def merge!(run, gaps, result, ingredient_paths, cuisine)
    merged_by_index = {}
    response_by_index = Array(result&.dig("items")).each_with_object({}) { |row, h| h[row["index"]] ||= row }

    run.transaction do
      # order(:id) keeps lock acquisition in PK order, matching
      # accept_all's find_each — inconsistent ordering could deadlock.
      locked = run.ingestion_items
                  .where(id: gaps.map { |g| g[:item_id] }, decision: "pending")
                  .order(:id).lock.index_by(&:id)

      rows = gaps.each_with_index.filter_map do |gap, index|
        item     = locked[gap[:item_id]]
        response = response_by_index[index]
        next if item.nil?

        merged = if response
          merge_ingredients(item, response.dig("ingredients", "resolved"), ingredient_paths)
        else
          Array(item.ingredients_payload)
        end
        # Reported for every locked dish, written or not: the wheat shadow
        # compares against what the dish carries, and a dish with nothing
        # new this attempt still has rows to compare.
        merged_by_index[index] = merged
        next if response.nil? && cuisine.nil?

        # ingestion_run_id: Postgres checks NOT NULL on the insert tuple
        # before ON CONFLICT resolves. unresolved_tags is not written:
        # it was Haiku's list of cuisine-ish phrases, and Jev answers
        # over the catalog, so there is nothing to collect.
        { id:                     item.id,
          ingestion_run_id:       run.id,
          ingredients_payload:    merged,
          tags_payload:           rebuild_tags(item, merged, cuisine&.fetch(index, []), ingredient_paths),
          unresolved_ingredients: response ? Array(response.dig("ingredients", "unresolved")) : item.unresolved_ingredients }
      end

      if rows.any?
        # upsert_all stamps updated_at itself (record_timestamps).
        IngestionItem.upsert_all(
          rows,
          update_only: %i[ingredients_payload tags_payload unresolved_ingredients]
        )
      end
    end
    merged_by_index
  end

  def merge_ingredients(item, ai_rows, ingredient_paths)
    merged = Array(item.ingredients_payload).dup
    known  = merged.map { |r| r["slug"] }.to_set
    claims = Ingestion::DietClaims.claims_in(Ingestion::MenuText.segments(item.name))

    Array(ai_rows).each do |row|
      slug = row["slug"]
      next if known.include?(slug)

      unless ingredient_paths.key?(slug)
        Rails.logger.warn("GapFillResolveJob: dropping unknown ingredient slug #{slug.inspect}")
        next
      end

      # Same gate as the resolver's implied bases (Ingestion::DietClaims):
      # the model is asked for implied ingredients, so without it a
      # "Gluten-Free Pizza" gets its suppressed crust right back.
      if Ingestion::DietClaims.contradicted?(claims, slug: slug, path: ingredient_paths[slug].to_s)
        Rails.logger.info(
          "GapFillResolveJob: dropping #{slug} — contradicts a diet claim in #{item.name.inspect}"
        )
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
  MACHINE_SOURCES = %w[match derived ai ingredient_derived].freeze

  # `cuisine_rows` nil means Jev could not answer this time: the `ai`
  # rows (only ever cuisine) a previous attempt landed are kept instead
  # of being rebuilt from nothing.
  def rebuild_tags(item, merged_ingredients, cuisine_rows, ingredient_paths)
    resolved = merged_ingredients.map do |r|
      { slug: r["slug"], path: ingredient_paths[r["slug"]].to_s,
        confidence: r["confidence"], source: r["source"] }
    end

    rebuilt = cuisine_rows.nil? ? MACHINE_SOURCES - [ "ai" ] : MACHINE_SOURCES
    tags = Array(item.tags_payload).reject { |r| rebuilt.include?(r["source"]) }
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
    # Jev's rows are keyed by our own leaf-cuisine slugs, so there is no
    # unknown slug to drop — only a keyword hit to avoid duplicating.
    Array(cuisine_rows).each do |row|
      slug = row["slug"]
      next if known.include?(slug)

      tags << Ingestion::AssociationPayload.dump(slug: slug, confidence: row["confidence"], source: "ai")
      known << slug
    end
    tags
  end
end
