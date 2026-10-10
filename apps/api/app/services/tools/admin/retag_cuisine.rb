# frozen_string_literal: true

module Tools
  module Admin
    # Re-decide a restaurant's cuisine tags with Jev. The way an admin
    # re-runs the cuisine half of enrichment on a menu that is already
    # live, without a re-scan.
    class RetagCuisine < Tools::AdminBase
      tool_name "retag_cuisine"
      title "Re-tag cuisine with Jev (admin)"
      description <<~TEXT
        Ask Jev (TypeSafe's yes/no model, which decides cuisine tags for
        every new scan since 2026-10-10) to re-decide the cuisine tags on a
        restaurant's published dishes, and rewrite them.

        Use it on a restaurant published before 2026-10-10, whose cuisine
        tags came from Haiku and tend to force a dish into the nearest
        cuisine (a Venezuelan menu tagged Mexican, chai tagged Indian), or
        on any menu whose cuisine tags look wrong. Call it with
        dry_run: true first to see what would change.

        Only cuisine-family tags are touched. A cuisine tag a person added
        or confirmed is kept. Other tag families, ingredients, and each
        dish's own confidence (what strict-mode filtering reads) are never
        changed. Nothing is written if Jev fails part-way.

        Returns the dishes whose cuisine set changed, with before and after
        slugs, plus counts of dishes left as they were and dishes Jev could
        not answer for.
      TEXT

      input_schema(
        properties: {
          restaurant: {
            type: "string",
            description: "Restaurant UUID or slug."
          },
          dry_run: {
            type: "boolean",
            description: "true = report what would change without writing anything. Default false."
          }
        },
        required: [ "restaurant" ]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      # Running it again re-decides the same tags; a person's rows are
      # never written to.
      unrecoverable_when { false }

      running_description { |args| args[:dry_run] ? "Previewing cuisine tags" : "Re-tagging cuisine" }

      def self.perform(context:, restaurant:, dry_run: false)
        context.admin!
        record = find_restaurant!(restaurant)
        unless ::Ingestion::JevCuisineTagger.enabled?
          raise Errors::Error.new("Jev is not configured on this server (JEV_API_KEY); nothing was changed.",
                                  code: "unavailable")
        end

        result = ::Ingestion::JevCuisineRetag.new(record).call(dry_run: dry_run)

        ok(
          restaurant: restaurant_row(record),
          dry_run:    result.dry_run,
          dishes:     result.dishes,
          changed:    result.changes.map { |c|
            { item_id: c.item.id, name: untrusted(c.item.name), before: c.before, after: c.after }
          },
          unchanged:  result.unchanged,
          unanswered: result.unanswered
        )
      rescue ::Ingestion::JevCuisineRetag::Unavailable => e
        raise Errors::Error.new("Jev did not answer; nothing was changed. Try again shortly. (#{e.message})",
                                code: "unavailable")
      end
    end
  end
end
