# frozen_string_literal: true

module Tools
  module Profile
    # Add to or remove from the caller's avoid lists.
    #
    # This tool is deliberately a DIFF, not a replacement, even though the
    # REST endpoint it shadows takes the full array. A web client computes
    # the complete list before it POSTs; a model reconstructing an array
    # from conversation would eventually drop an allergen nobody mentioned
    # this turn, and the failure mode there is someone eating something
    # that hurts them. Add and remove are explicit, or nothing happens.
    class UpdateAvoidLists < Tools::Base
      audience :user

      tool_name "update_avoid_lists"
      title "Update what the caller avoids"
      description <<~TEXT
        Add to or remove from the signed-in caller's avoid lists. Avoided
        ingredients and tags hide dishes, so this directly changes what the
        user is shown.

        Pass slugs from `search_taxonomy` — never guess a slug, and never
        invent one. Unknown slugs are rejected without changing anything.

        This applies a diff. Only the slugs you pass are touched; everything
        else in the profile is left alone. There is no way to replace the
        whole list at once, by design.

        REMOVING an avoid un-hides dishes and is the direction that can hurt
        someone. Only remove when the user has clearly asked for that specific
        thing, confirm what you are about to remove first, and never remove an
        allergen as a side effect of some other request. Adding is safe.

        `apply_preset` unions a ready-made preset's avoid lists on top of what
        the user already has. Presets only ever add.
      TEXT

      input_schema(
        properties: {
          add_ingredients:    { type: "array", items: { type: "string" }, description: "Ingredient slugs to start avoiding." },
          remove_ingredients: { type: "array", items: { type: "string" }, description: "Ingredient slugs to stop avoiding. Confirm with the user first." },
          add_tags:           { type: "array", items: { type: "string" }, description: "Tag slugs to start avoiding." },
          remove_tags:        { type: "array", items: { type: "string" }, description: "Tag slugs to stop avoiding. Confirm with the user first." },
          apply_preset:       { type: "string", description: "Dietary preset slug whose avoid lists are unioned onto the profile." }
        },
        required: []
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, add_ingredients: nil, remove_ingredients: nil,
                       add_tags: nil, remove_tags: nil, apply_preset: nil)
        profile = context.user!.profile

        adds_i    = resolve(Ingredient, add_ingredients,    "ingredient")
        removes_i = resolve(Ingredient, remove_ingredients, "ingredient")
        adds_t    = resolve(Tag,        add_tags,           "tag")
        removes_t = resolve(Tag,        remove_tags,        "tag")

        if [adds_i, removes_i, adds_t, removes_t].all?(&:empty?) && apply_preset.blank?
          raise Errors::InvalidArgument, "Nothing to do — pass at least one slug to add or remove, or a preset to apply."
        end

        preset = nil
        if apply_preset.present?
          preset = DietaryProfile.find_by(slug: apply_preset)
          raise Errors::NotFound, "No dietary preset with slug #{apply_preset.inspect}. Try search_taxonomy." if preset.nil?
        end

        before = { ingredients: profile.avoid_ingredient_ids, tags: profile.avoid_tag_ids }

        profile.avoid_ingredient_ids =
          apply_diff(before[:ingredients], adds_i.map(&:id) + Array(preset&.avoid_ingredient_ids), removes_i.map(&:id))
        profile.avoid_tag_ids =
          apply_diff(before[:tags], adds_t.map(&:id) + Array(preset&.avoid_tag_ids), removes_t.map(&:id))
        profile.primary_dietary_profile_id = preset.id if preset

        profile.save!

        ok(
          added:   { ingredients: adds_i.map(&:slug),    tags: adds_t.map(&:slug) },
          removed: { ingredients: removes_i.map(&:slug), tags: removes_t.map(&:slug) },
          applied_preset: preset&.slug,
          profile: Serializer.call(profile.reload)
        )
      end

      # Removes win over adds so a slug passed in both lists ends up
      # removed rather than in an order-dependent state.
      def self.apply_diff(current, add_ids, remove_ids)
        ((current + add_ids).uniq - remove_ids)
      end
      private_class_method :apply_diff

      # All-or-nothing: one bad slug rejects the whole call rather than
      # silently applying a partial change the model would then report as
      # complete.
      def self.resolve(model, slugs, label)
        list = Array(slugs).map(&:to_s).reject(&:blank?).uniq
        return [] if list.empty?

        found = model.where(slug: list).to_a
        missing = list - found.map(&:slug)
        if missing.any?
          raise Errors::InvalidArgument,
                "Unknown #{label} slug(s): #{missing.join(', ')}. Use search_taxonomy to find the right ones."
        end

        found
      end
      private_class_method :resolve
    end
  end
end
