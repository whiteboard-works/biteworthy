# frozen_string_literal: true

module Admin
  # Rewrite published items' join-row source/confidence from the accepted
  # ingestion item's reviewed payload, under the locked confidence rules.
  #
  # May only LOWER dish/join confidence or ADD wheat/gluten rows. Never
  # raises confidence and never removes an allergen. Idempotent.
  class BackfillConfidence
    ALLERGEN_TAG_SLUGS = %w[
      contains-gluten contains-dairy contains-egg contains-fish
      contains-shellfish contains-soy contains-sesame contains-tree-nut
      contains-peanut
    ].freeze
    WHEAT_PREFIX = "grain.wheat"

    def self.call(restaurant:, dry_run: true)
      new(restaurant: restaurant, dry_run: dry_run).call
    end

    def initialize(restaurant:, dry_run:)
      @restaurant = restaurant
      @dry_run = dry_run
      @results = []
    end

    def call
      items_to_backfill.find_each { |item| backfill_item(item) }

      {
        dry_run: @dry_run,
        restaurant_id: @restaurant.id,
        restaurant_name: @restaurant.name,
        items_processed: @results.size,
        items: @results
      }
    end

    private

    def items_to_backfill
      @restaurant.items.published.where(
        id: IngestionItem.where(decision: "accepted").select(:item_id)
      )
    end

    def backfill_item(item)
      ingestion_item = item.ingestion_items.where(decision: "accepted").order(decided_at: :desc).first
      return unless ingestion_item

      decided_by = ingestion_item.ingestion_run.user
      old_confidence = item.confidence
      changes = []
      allergen_rows_added = []

      planned_ingredient_confidences = item.item_ingredients.pluck(:id, :confidence).to_h

      backfill_joins(
        item: item,
        model: ItemIngredient,
        payload: ingestion_item.ingredients_payload,
        decided_by: decided_by,
        planned_confidences: planned_ingredient_confidences
      ).each do |change|
        changes << change
        allergen_rows_added << change[:slug] if wheat_slug?(change[:slug]) && change[:type] == :added
      end

      backfill_joins(
        item: item,
        model: ItemTag,
        payload: ingestion_item.tags_payload,
        decided_by: decided_by,
        planned_confidences: {}
      ).each do |change|
        changes << change
        if change[:type] == :added && ALLERGEN_TAG_SLUGS.include?(change[:slug])
          allergen_rows_added << change[:slug]
        end
      end

      new_confidence = Ingestion::ConfidenceMapper.dish_confidence_from_ingredients(
        planned_ingredient_confidences.values.map { |c| { confidence: c } }
      )
      if confidence_rank(new_confidence) > confidence_rank(old_confidence)
        new_confidence = old_confidence
      end

      unless @dry_run
        item.update!(confidence: new_confidence) if new_confidence != old_confidence
      end

      return if changes.empty? && old_confidence == new_confidence

      @results << {
        item_id: item.id,
        item_name: item.name,
        old_confidence: old_confidence,
        new_confidence: new_confidence,
        rows_changed: changes.size,
        changes: changes,
        allergen_rows_added: allergen_rows_added
      }
    end

    def backfill_joins(item:, model:, payload:, decided_by:, planned_confidences:)
      changes = []
      payload_rows = Ingestion::AssociationPayload.load_all(payload)
      slugs = payload_rows.filter_map { |row| row.slug.presence }.uniq
      node_model = model == ItemIngredient ? Ingredient : Tag
      by_slug = node_model.where(slug: slugs).index_by(&:slug)
      foreign_key = model.denormalized_foreign_key

      payload_rows.each do |payload_row|
        node = by_slug[payload_row.slug]
        next unless node

        mapped = Ingestion::ConfidenceMapper.map_row(payload_row, decided_by: decided_by)
        existing = model.find_by(:item_id => item.id, foreign_key => node.id)

        if existing
          next unless should_rewrite?(existing, mapped)

          # Capture before update — apply mode would otherwise report
          # the post-save source/confidence as the old values.
          old_source = existing.source
          old_confidence = existing.confidence

          unless @dry_run
            existing.update!(source: mapped[:source], confidence: mapped[:confidence])
          end
          planned_confidences[existing.id] = mapped[:confidence] if model == ItemIngredient

          changes << {
            type: :updated,
            model: model.name,
            slug: payload_row.slug,
            old_source: old_source,
            new_source: mapped[:source],
            old_confidence: old_confidence,
            new_confidence: mapped[:confidence]
          }
        elsif allowed_add?(model, node, payload_row.slug)
          unless @dry_run
            created = model.create!(
              :item_id => item.id,
              foreign_key => node.id,
              :source => mapped[:source],
              :confidence => mapped[:confidence]
            )
            planned_confidences[created.id] = mapped[:confidence] if model == ItemIngredient
          end
          planned_confidences["new-#{node.id}"] = mapped[:confidence] if model == ItemIngredient && @dry_run

          changes << {
            type: :added,
            model: model.name,
            slug: payload_row.slug,
            source: mapped[:source],
            confidence: mapped[:confidence]
          }
        end
      end

      changes
    end

    def should_rewrite?(existing, mapped)
      weaker = confidence_rank(mapped[:confidence]) < confidence_rank(existing.confidence)
      source_changed = existing.source != mapped[:source] &&
                       confidence_rank(mapped[:confidence]) <= confidence_rank(existing.confidence)
      weaker || source_changed
    end

    def allowed_add?(model, node, slug)
      return wheat_slug?(slug) || wheat_path?(node) if model == ItemIngredient

      ALLERGEN_TAG_SLUGS.include?(slug)
    end

    def wheat_slug?(slug)
      slug.to_s.start_with?("grain-wheat")
    end

    def wheat_path?(node)
      node.respond_to?(:path) && node.path.to_s.start_with?(WHEAT_PREFIX)
    end

    def confidence_rank(conf)
      { "confirmed" => 3, "suggested" => 2, "inferred" => 1 }[conf] || 0
    end
  end
end
