# Background LLM enrichment pass, enqueued by ResolveItemsJob after the
# run is already :staged and usable. One Haiku call covering only the
# items the deterministic resolver flagged as gaps, asking only for what
# code can't derive: implied ingredients + cuisine tags.
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

    out = timed_anthropic_call(
      run,
      api_error:        "gap_fill_api_error",
      validation_error: "gap_fill_validation_failed",
      model:            resolve_model,
      fail_run:         false
    ) do |client|
      client.messages_create(
        system:          Ingestion::GapFillPrompt.system(client),
        messages:        Ingestion::GapFillPrompt.user_messages(gaps.map { |g| g[:prompt_row] }),
        response_schema: Ingestion::GapFillSchema
      )
    end
    if out.nil?
      run.update!(enrichment_status: "failed")
      return
    end
    result, = out

    merge!(run, gaps, result)
    run.update!(enrichment_status: "completed")
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

  def merge!(run, gaps, result)
    response_by_index = Array(result["items"]).each_with_object({}) { |row, h| h[row["index"]] ||= row }
    ingredient_paths  = Ingredient.pluck(:slug, :path).to_h
    cuisine_slugs     = Tag.where(family: "cuisine").pluck(:slug).to_set

    run.transaction do
      locked = run.ingestion_items
                  .where(id: gaps.map { |g| g[:item_id] }, decision: "pending")
                  .lock.index_by(&:id)

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

      merged << { "slug" => slug, "confidence" => row["confidence"], "source" => "ai" }
      known << slug
    end
    merged
  end

  def rebuild_tags(item, merged_ingredients, ai_cuisine_rows, ingredient_paths, cuisine_slugs)
    resolved = merged_ingredients.map do |r|
      { slug: r["slug"], path: ingredient_paths[r["slug"]].to_s,
        confidence: r["confidence"], source: r["source"] }
    end

    tags = Ingestion::TagDeriver.derive(
      segments:             Ingestion::MenuText.segments(item.name, item.description),
      section_segments:     Ingestion::MenuText.segments(item.section_name),
      resolved_ingredients: resolved
    ).map { |t| { "slug" => t[:slug], "confidence" => t[:confidence], "source" => t[:source] } }

    known = tags.map { |t| t["slug"] }.to_set
    Array(ai_cuisine_rows).each do |row|
      slug = row["slug"]
      next if known.include?(slug)

      unless cuisine_slugs.include?(slug)
        Rails.logger.warn("GapFillResolveJob: dropping unknown cuisine tag slug #{slug.inspect}")
        next
      end

      tags << { "slug" => slug, "confidence" => row["confidence"], "source" => "ai" }
      known << slug
    end
    tags
  end
end
