# frozen_string_literal: true

module Tools
  module Taxonomy
    # Shared plumbing for the ingredient/tag taxonomy tools.
    #
    # Ingredients and tags are near-identical trees with different
    # metadata, so `kind` picks the model rather than doubling the tool
    # count — a model choosing between `create_ingredient` and
    # `create_tag` alongside four other near-twins misroutes.
    #
    # The v1 rails, carried over from the admin REST endpoints:
    #
    #   * `slug` and `path` are IMMUTABLE. Ingestion payloads resolve by
    #     slug at promote time, so renaming one silently drops joins —
    #     an allergen-safety P0 — and an ltree path rename orphans every
    #     descendant, because nothing cascades.
    #   * `family` is immutable on tags: allergen-family tags feed the
    #     filter's avoid arrays, and re-classifying one silently changes
    #     what gets hidden.
    #   * Deleting is refused while anything points at the node.
    class Base < Tools::AdminBase
      KINDS = %w[ingredient tag].freeze
      LTREE_PATH_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/

      KIND_PROPERTY = {
        type: "string",
        description: "Which tree. Ingredients are things in food; tags are labels like 'contains-dairy' or 'vegan'.",
        enum: KINDS
      }.freeze

      class << self
        def model_for(kind)
          raise Errors::InvalidArgument, "kind must be one of: #{KINDS.join(', ')}." unless KINDS.include?(kind)

          kind == "ingredient" ? Ingredient : Tag
        end

        def find_node!(kind, slug)
          model_for(kind).find_by(slug: slug.to_s) ||
            raise(Errors::NotFound, "No #{kind} with slug '#{slug}'.")
        end

        def validate_path!(kind, path)
          unless path.to_s.match?(LTREE_PATH_FORMAT)
            raise Errors::InvalidArgument,
                  "path must be lowercase dot-separated segments, e.g. 'dairy.cheese.cheddar'."
          end

          parent = path.to_s.rpartition(".").first
          return if parent.blank? || model_for(kind).exists?(path: parent)

          raise Errors::InvalidArgument, "Create the parent '#{parent}' first."
        end

        # Every place a node can still be referenced. A delete that
        # ignored these would drop a node out of somebody's avoid list —
        # UserProfile tolerates stale ids on read, so the filter would
        # silently weaken rather than fail loudly.
        def references(node, kind)
          if kind == "ingredient"
            {
              descendants: Ingredient.descendants_of(node.path).where.not(id: node.id).count,
              items:       ItemIngredient.where(ingredient_id: node.id).count,
              presets:     DietaryProfileIngredient.where(ingredient_id: node.id).count,
              modifiers:   ItemModifier.where("ingredient_ids @> ARRAY[:id]::uuid[]", id: node.id).count,
              profiles:    profiles_referencing(node.id, kind)
            }
          else
            {
              descendants: Tag.descendants_of(node.path).where.not(id: node.id).count,
              items:       ItemTag.where(tag_id: node.id).count,
              presets:     DietaryProfileTag.where(tag_id: node.id).count,
              modifiers:   ItemModifier.where("tag_ids @> ARRAY[:id]::uuid[]", id: node.id).count,
              profiles:    profiles_referencing(node.id, kind)
            }
          end
        end

        def node_row(node, kind)
          row = {
            kind: kind,
            slug: node.slug,
            name: node.name,
            path: node.path.to_s
          }
          if kind == "ingredient"
            row.merge(aliases: node.aliases, allergen: node.allergen)
          else
            row.merge(family: node.family, description: node.description)
          end
        end

        private

        def profiles_referencing(id, kind)
          column = kind == "ingredient" ? "ingredient_ids" : "tag_ids"
          UserProfile.where(
            "avoid_#{column} @> ARRAY[:id]::uuid[] OR " \
            "liked_#{column} @> ARRAY[:id]::uuid[] OR " \
            "disliked_#{column} @> ARRAY[:id]::uuid[]",
            id: id
          ).count
        end
      end
    end
  end
end
