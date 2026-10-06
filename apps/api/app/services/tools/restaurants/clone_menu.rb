# frozen_string_literal: true

module Tools
  module Restaurants
    # Copy an already-accepted menu onto a sibling location. Community
    # creators can do this for restaurants they created; admins can clone
    # any readable source onto any target.
    class CloneMenu < Tools::Base
      audience :user

      tool_name "clone_menu"
      title "Clone a menu to a sibling location"
      description <<~TEXT
        Copy published dishes from one restaurant onto another whose menu
        is still empty. Use this after importing a multi-location brand
        from one own-site menu: scan and accept once, then clone onto
        each sibling. Hours, address, and phone stay per location.

        Only clone when the site (or the user) says the menus match. If
        they differ, start_menu_scan each location from its own source
        instead.

        The target must have no dishes yet. Confidence and source on
        every ingredient and tag are copied as-is — this does not
        re-extract and does not confirm unverified data.
      TEXT

      input_schema(
        properties: {
          source_restaurant: {
            type: "string",
            description: "Slug or UUID of the restaurant whose published menu to copy."
          },
          target_restaurant: {
            type: "string",
            description: "Slug or UUID of the empty sibling to copy onto."
          }
        },
        required: %w[source_restaurant target_restaurant]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false)

      running_description { "Copying the menu to the other location" }

      # Re-cloning is refused once the target has dishes; an admin can
      # still edit or remove the copies.
      unrecoverable_when { false }

      def self.perform(context:, source_restaurant:, target_restaurant:)
        user   = context.user!
        source = Restaurant.kept.find_by_id_or_slug!(source_restaurant)
        target = Restaurant.kept.find_by_id_or_slug!(target_restaurant)

        result = ::Menus::Clone.call(source: source, target: target, actor: user)
        ok(
          cloned:          true,
          items_cloned:    result.items_cloned,
          sections_cloned: result.sections_cloned,
          source:          result.source,
          target:          result.target,
          next_step:       "Hours and address stay on each restaurant. Scan a sibling separately if its menu differs."
        )
      rescue ::Menus::Clone::Error => e
        raise Errors::InvalidArgument, e.message
      end
    end
  end
end
