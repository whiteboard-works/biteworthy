# frozen_string_literal: true

module Tools
  module Admin
    # Check scan status plus list staged items in one call. Combines
    # get_scan_status and list_staged_items for the admin flow where polling
    # separately is less useful.
    class GetScan < Tools::AdminBase
      tool_name "get_scan"
      title "Get scan status and items (admin)"
      description <<~TEXT
        Check a scan's status and retrieve its staged items in one call.

        Returns status, ready flag, failure_message if failed, and the full
        list of staged items with ingredients, tags, confidence, and
        needs_attention flags.

        Use this after start_scan. Poll until ready: true, then review items
        and call accept_items or reject_items.
      TEXT

      input_schema(
        properties: {
          scan_id: {
            type: "string",
            description: "Scan id from start_scan."
          }
        },
        required: [ "scan_id" ]
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { "Fetching scan" }

      def self.perform(context:, scan_id:)
        context.admin!
        run = Tools::Ingestion::Base.find_run!(context, scan_id)

        items = run.ingestion_items.includes(:matched_item).order(:position, :created_at).to_a
        taxonomy_names = load_taxonomy_names(items)

        pending_count = items.count { |i| i.decision == "pending" }
        accepted_count = items.count { |i| i.decision == "accepted" }
        rejected_count = items.count { |i| i.decision == "rejected" }
        edited_count = items.count { |i| i.decision == "edited" }
        remaining_count = pending_count + edited_count

        ok(
          scan_id: run.id,
          status: run.status,
          ready: run.staged? || run.published?,
          failed: run.failed?,
          failure_message: run.failure_message,
          enrichment_status: run.enrichment_status,
          restaurant: { id: run.restaurant_id, slug: run.restaurant&.slug, name: run.restaurant&.name },
          dish_count: items.size,
          pending_count: pending_count,
          accepted_count: accepted_count,
          rejected_count: rejected_count,
          edited_count: edited_count,
          remaining_count: remaining_count,
          items: items.map { |item| serialize_item(item, taxonomy_names) }
        )
      end

      def self.serialize_item(item, taxonomy_names)
        ingredients = ::Ingestion::AssociationPayload.load_all(item.ingredients_payload)
        tags = ::Ingestion::AssociationPayload.load_all(item.tags_payload)
        prices = Array(item.prices_payload).filter_map do |row|
          row = row.with_indifferent_access
          next if row[:price_cents].blank?
          {
            size: row[:size],
            price_cents: row[:price_cents],
            currency: row[:currency] || "USD"
          }
        end

        {
          id: item.id,
          name: untrusted(item.name),
          description: untrusted(item.description),
          section: item.section_name,
          position: item.position,
          decision: item.decision,
          needs_attention: item.needs_attention?,
          prices: prices,
          ingredients: ingredients.map { |row|
            {
              slug: row.slug,
              name: taxonomy_names[:ingredients][row.slug] || row.slug,
              confidence: row.confidence,
              source: row.source
            }
          },
          tags: tags.map { |row|
            {
              slug: row.slug,
              name: taxonomy_names[:tags][row.slug] || row.slug,
              confidence: row.confidence,
              source: row.source
            }
          },
          unresolved_ingredients: item.unresolved_ingredients,
          unresolved_tags: item.unresolved_tags,
          updates_existing_item: item.matched_item_id.present?,
          matched_item_id: item.matched_item_id
        }
      end
      private_class_method :serialize_item

      def self.load_taxonomy_names(items)
        ingredient_slugs = items.flat_map { |i|
          ::Ingestion::AssociationPayload.load_all(i.ingredients_payload).map(&:slug)
        }.uniq
        tag_slugs = items.flat_map { |i|
          ::Ingestion::AssociationPayload.load_all(i.tags_payload).map(&:slug)
        }.uniq

        {
          ingredients: Ingredient.where(slug: ingredient_slugs).pluck(:slug, :name).to_h,
          tags: Tag.where(slug: tag_slugs).pluck(:slug, :name).to_h
        }
      end
      private_class_method :load_taxonomy_names
    end
  end
end
