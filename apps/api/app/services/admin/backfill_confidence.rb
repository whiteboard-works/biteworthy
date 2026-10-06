# frozen_string_literal: true

module Admin
  # Backfill source and confidence for published items from their accepted ingestion items.
  # Re-applies the locked confidence rules to existing prod data that was promoted before
  # the rules were fixed (PR 766 follow-up).
  #
  # For each published item with a linked accepted ingestion item (ingestion_items.item_id),
  # rewrites the item's ingredient and tag rows' source and confidence from that staged item's
  # reviewed list under the locked rules, then re-derives the dish confidence.
  #
  # May only LOWER confidence or ADD wheat/gluten rows, never raise confidence or remove an allergen.
  #
  # Idempotent: running twice produces the same result.
  #
  # Usage:
  #   Admin::BackfillConfidence.call(restaurant: restaurant, dry_run: true)
  class BackfillConfidence
    def self.call(restaurant:, dry_run: true)
      new(restaurant: restaurant, dry_run: dry_run).call
    end

    def initialize(restaurant:, dry_run:)
      @restaurant = restaurant
      @dry_run = dry_run
      @results = []
    end

    def call
      items_to_backfill.find_each do |item|
        backfill_item(item)
      end

      {
        dry_run: @dry_run,
        restaurant_id: @restaurant.id,
        restaurant_name: @restaurant.name,
        items_processed: @results.count,
        items: @results
      }
    end

    private

    def items_to_backfill
      # Published items that have an accepted ingestion item
      @restaurant.items.published
                 .joins("INNER JOIN ingestion_items ON ingestion_items.item_id = items.id")
                 .where(ingestion_items: { decision: "accepted" })
                 .includes(:item_ingredients, :item_tags, :ingestion_items)
    end

    def backfill_item(item)
      # Find the most recent accepted ingestion item for this published item
      ingestion_item = item.ingestion_items.where(decision: "accepted").order(decided_at: :desc).first
      return unless ingestion_item

      old_confidence = item.confidence
      changes = []
      allergen_rows_added = []

      # Get the decided_by user to determine accept confidence
      decided_by = User.find_by(id: ingestion_item.ingestion_run.user_id)

      # Backfill ingredients
      ingredient_changes = backfill_joins(
        item: item,
        model: ItemIngredient,
        payload: ingestion_item.ingredients_payload,
        decided_by: decided_by
      )
      changes.concat(ingredient_changes)

      # Backfill tags
      tag_changes = backfill_joins(
        item: item,
        model: ItemTag,
        payload: ingestion_item.tags_payload,
        decided_by: decided_by
      )
      changes.concat(tag_changes)

      # Track allergen rows that were added
      allergen_tags = %w[contains-gluten contains-dairy contains-egg contains-fish
                         contains-shellfish contains-soy contains-sesame contains-tree-nut
                         contains-peanut]
      tag_changes.each do |change|
        if change[:type] == :added && allergen_tags.include?(change[:slug])
          allergen_rows_added << change[:slug]
        end
      end

      # Re-derive dish confidence
      new_confidence = derive_dish_confidence(item)

      # Only proceed if confidence lowered or stayed the same
      if confidence_rank(new_confidence) > confidence_rank(old_confidence)
        Rails.logger.warn(
          "BackfillConfidence: Item #{item.id} would upgrade #{old_confidence} → #{new_confidence}, skipping"
        )
        return
      end

      unless @dry_run
        item.update!(confidence: new_confidence) if new_confidence != old_confidence
      end

      if changes.any? || old_confidence != new_confidence
        @results << {
          item_id: item.id,
          item_name: item.name,
          old_confidence: old_confidence,
          new_confidence: new_confidence,
          changes: changes,
          allergen_rows_added: allergen_rows_added
        }
      end
    end

    def backfill_joins(item:, model:, payload:, decided_by:)
      changes = []
      payload_rows = Ingestion::AssociationPayload.load_all(payload)

      # Map payload slugs to nodes
      slugs = payload_rows.filter_map { |row| row.slug.presence }.uniq
      node_model = model == ItemIngredient ? Ingredient : Tag
      by_slug = node_model.where(slug: slugs).index_by(&:slug)

      payload_rows.each do |payload_row|
        node = by_slug[payload_row.slug]
        next unless node

        # Find existing join row
        foreign_key = model == ItemIngredient ? :ingredient_id : :tag_id
        existing = model.find_by(item_id: item.id, foreign_key => node.id)

        # Map confidence per locked rules
        mapped = Ingestion::ConfidenceMapper.map_row(payload_row, decided_by: decided_by)

        if existing
          # Update if confidence lowered or source changed
          if existing.source != mapped[:source] ||
             confidence_rank(mapped[:confidence]) < confidence_rank(existing.confidence)
            old_source = existing.source
            old_conf = existing.confidence

            unless @dry_run
              existing.update!(source: mapped[:source], confidence: mapped[:confidence])
            end

            changes << {
              type: :updated,
              model: model.name,
              slug: payload_row.slug,
              old_source: old_source,
              new_source: mapped[:source],
              old_confidence: old_conf,
              new_confidence: mapped[:confidence]
            }
          end
        else
          # Add missing row (e.g., a wheat ingredient that wasn't there before)
          unless @dry_run
            model.create!(
              item_id: item.id,
              foreign_key => node.id,
              source: mapped[:source],
              confidence: mapped[:confidence]
            )
          end

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

    def derive_dish_confidence(item)
      ingredient_confidences = item.item_ingredients.pluck(:confidence)
      return "suggested" if ingredient_confidences.empty?
      return "inferred" if ingredient_confidences.include?("inferred")
      return "suggested" if ingredient_confidences.include?("suggested")

      "confirmed"
    end

    def confidence_rank(conf)
      { "confirmed" => 3, "suggested" => 2, "inferred" => 1 }[conf] || 0
    end
  end
end
