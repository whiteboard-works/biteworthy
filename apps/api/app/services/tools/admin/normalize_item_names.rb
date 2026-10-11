# frozen_string_literal: true

module Tools
  module Admin
    # Applies the naming standard (`Names::Standard`) to a restaurant's
    # dishes saved before it existed. New writes are already normalized.
    class NormalizeItemNames < Tools::AdminBase
      tool_name "normalize_item_names"
      title "Fix all-caps dish names (admin)"
      description <<~TEXT
        Rewrite a restaurant's dish names and descriptions to the BiteWorthy
        naming standard: a name printed mostly in capitals becomes Title Case
        ("CHICKEN TIKKA MASALA" → "Chicken Tikka Masala"), a description in
        capitals becomes sentence case, and a footnote asterisk at either end
        of a name ("Tuna Tartare*") is removed. Text that is already mixed
        case is left alone, and short all-caps names (BLT) are kept.

        Every dish at the restaurant is checked, whatever its status. Call it
        with dry_run: true first to see what would change. A real run asks
        for confirmation first; a dry run does not.

        Returns `written`, the number of dishes changed, and `changed`, each
        with its name and description before and after, plus `stale`, dishes
        edited while it ran and left alone (run again), and `locked`, dishes
        the restaurant verified that you may not edit, left alone. Running it twice
        changes nothing the second time.
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

      # Same gate shape as retag_cuisine: a dry run is never parked, a
      # real run asks first. The old text is only in the response.
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)
      unrecoverable_when { |args| !args[:dry_run] }
      confirm_when { |args| !args[:dry_run] }
      confirmation_prompt do |args|
        "Rewrite the all-caps dish names and descriptions at #{args[:restaurant]} to the " \
        "BiteWorthy naming standard? The original text is not kept."
      end

      running_description { |args| args[:dry_run] ? "Previewing name fixes" : "Fixing dish names" }

      def self.text_row(text)
        { name: untrusted(text[:name]), description: untrusted(text[:description].presence) }
      end

      def self.perform(context:, restaurant:, dry_run: false)
        context.admin!
        record  = find_restaurant!(restaurant)
        result  = ::Names::Backfill.new(record.items, editable: ->(item) { item.can_be_edited_by?(context.user) })
                                   .call(dry_run: dry_run)

        ok(
          restaurant: restaurant_row(record),
          dry_run:    dry_run,
          written:    result.changes.size,
          changed:    result.changes.map { |c| { item_id: c.item.id, before: text_row(c.before), after: text_row(c.after) } },
          stale:      result.stale,
          locked:     result.locked
        )
      end
    end
  end
end
