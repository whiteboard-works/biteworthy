# frozen_string_literal: true

module Tools
  module Discovery
    # Resolve free text to the taxonomy slugs the write tools expect.
    #
    # Every profile-writing tool takes slugs, never names — "cheddar" is
    # ambiguous, `dairy-cheddar` is not. This is the lookup that closes
    # that gap, and it searches aliases too, so "garbanzo" finds chickpea.
    class SearchTaxonomy < Tools::Base
      audience :public

      tool_name "search_taxonomy"
      title "Search ingredients, tags, and diet presets"
      description <<~TEXT
        Look up the canonical slug for an ingredient, tag, or dietary preset.

        Call this before `update_avoid_lists` or any tool that takes a slug —
        never guess a slug from a user's wording. Aliases are searched too, so
        "garbanzo" resolves to the chickpea ingredient.

        `kind` narrows the search: "ingredient" (a food, e.g. cheddar),
        "tag" (a property, e.g. vegan / gluten-free / grilled / thai), or
        "preset" (a ready-made dietary profile the user can adopt wholesale).
        Omit it to search all three.
      TEXT

      input_schema(
        properties: {
          query: {
            type: "string",
            description: "Free text to match against names and aliases. Omit with kind=preset to list every preset."
          },
          kind: {
            type: "string",
            description: "Restrict to one taxonomy. Omit to search all.",
            enum: %w[ingredient tag preset]
          },
          limit: {
            type: "integer",
            description: "Maximum results per taxonomy (1-50, default 15).",
            minimum: 1,
            maximum: 50
          }
        },
        required: []
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { |args| "Looking up #{args[:query]}" }

      MAX_LIMIT     = 50
      DEFAULT_LIMIT = 15

      def self.perform(context:, query: nil, kind: nil, limit: nil)
        capped  = (limit || DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
        kinds   = kind.present? ? [kind] : %w[ingredient tag preset]
        results = {}

        results[:ingredients] = ingredients(query, capped) if kinds.include?("ingredient")
        results[:tags]        = tags(query, capped)        if kinds.include?("tag")
        results[:presets]     = presets(query, capped)     if kinds.include?("preset")

        ok(**results)
      end

      # ILIKE on name plus an aliases scan — the same pair the ingredients
      # endpoint uses, because the trigram threshold alone misses short
      # queries.
      def self.ingredients(query, limit)
        scope = Ingredient.order(:path).limit(limit)
        if query.present?
          scope = scope.where(
            "name ILIKE :q OR EXISTS (SELECT 1 FROM unnest(aliases) AS a WHERE a ILIKE :q)",
            q: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          )
        end
        scope.map do |i|
          { slug: i.slug, name: i.name, family: i.path.to_s.split(".").first, allergen: i.allergen }
        end
      end
      private_class_method :ingredients

      def self.tags(query, limit)
        scope = Tag.order(:family, :name).limit(limit)
        if query.present?
          scope = scope.where("name ILIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
        end
        scope.map { |t| { slug: t.slug, name: t.name, family: t.family } }
      end
      private_class_method :tags

      def self.presets(query, limit)
        scope = DietaryProfile.order(:name).limit(limit)
        if query.present?
          scope = scope.where("name ILIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
        end
        scope.map { |p| { slug: p.slug, name: p.name } }
      end
      private_class_method :presets
    end
  end
end
