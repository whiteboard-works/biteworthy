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

        Only cuisine tags a model wrote are replaced. A cuisine tag a
        person added or confirmed, or one derived from the menu's own
        wording, is kept. Other tag families, ingredients, and each dish's
        own confidence (what strict-mode filtering reads) are never
        changed. Nothing is written if Jev fails part-way. A real run asks
        for confirmation first; a dry run does not.

        Returns the dishes whose cuisine slugs changed (`changed`) apart
        from those where only a confidence grade moved (`regraded`), each
        with the rows before and after, plus counts of dishes left
        as they were, dishes Jev could not answer for, and dishes edited
        while Jev was answering (stale, left alone; run again). Running
        it twice re-decides the same dishes from the same text.
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

      # The static hint stays off so a dry run is never parked; the
      # argument gate below is what puts a person in front of a real run,
      # on both doors, and `unrecoverable_when` is what parks it in the
      # chat's accept_edits mode. Same shape as update_avoid_lists.
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)
      # A real run replaces the model-written rows and nothing restores
      # them; a dry run writes nothing.
      unrecoverable_when { |args| !args[:dry_run] }
      confirm_when { |args| !args[:dry_run] }
      confirmation_prompt do |args|
        "Rewrite the cuisine tags on every published dish at #{args[:restaurant]} from Jev's " \
        "answers? Tags a person added or confirmed stay; the model-written ones are replaced " \
        "and cannot be restored."
      end

      running_description { |args| args[:dry_run] ? "Previewing cuisine tags" : "Re-tagging cuisine" }

      def self.change_row(change)
        { item_id: change.item.id, name: untrusted(change.item.name), before: change.before, after: change.after }
      end

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
          changed:    result.changes.reject(&:regrade).map { |c| change_row(c) },
          regraded:   result.changes.select(&:regrade).map { |c| change_row(c) },
          unchanged:  result.unchanged,
          unanswered: result.unanswered,
          stale:      result.stale
        )
      rescue ::Ingestion::JevCuisineRetag::Unavailable => e
        raise Errors::Error.new("Jev did not answer; nothing was changed. Try again shortly. (#{e.message})",
                                code: "unavailable")
      end
    end
  end
end
