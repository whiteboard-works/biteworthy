# frozen_string_literal: true

# The rules for writing the ingredient and tag trees.
#
# Extracted from three copies that had already drifted:
# Api::V1::Admin::IngredientsController, Api::V1::Admin::TagsController,
# and Tools::Taxonomy::Base. The tag controller counted `prefer_tag_ids`
# when deciding whether a node was still referenced; the tool did not, so
# a tag nobody had done anything with except prefer it was undeletable
# over REST and deletable over MCP. Same taxonomy, two answers.
#
# The rails themselves are unchanged and are why this is worth owning in
# one place:
#
#   - `slug` and `path` are IMMUTABLE, and so is a tag's `family`.
#     Ingestion payloads resolve by slug at promote time, so a rename
#     silently drops joins (an allergen-safety P0); an ltree path rename
#     orphans every descendant because nothing cascades; and allergen
#     families feed the filter's avoid arrays, so re-classifying one
#     silently changes what gets hidden.
#   - A node's parent must exist before the node does — allergen
#     derivation walks ancestry, so an orphan path produces wrong
#     allergen data for every dish that uses it.
#   - Deleting is refused while anything still points at the node.
#
# Callers keep their own wire shapes: this raises typed errors and the
# adapters render them (REST as `{error:, references:}`, the tools as
# Tools::Errors).
module Taxonomy
  class Writer
    class Error < StandardError; end

    class InvalidPath < Error
      def initialize(path)
        super("#{path.inspect} is not a dotted lowercase ltree path")
      end
    end

    class ParentMissing < Error
      attr_reader :parent

      def initialize(parent)
        @parent = parent
        super("parent path '#{parent}' does not exist")
      end
    end

    class ImmutableField < Error
      attr_reader :fields

      def initialize(fields)
        @fields = fields
        super("cannot change #{fields.join(', ')} after create")
      end
    end

    class InUse < Error
      attr_reader :references

      def initialize(references)
        @references = references
        super("still referenced by #{references.select { |_, n| n.positive? }.keys.join(', ')}")
      end
    end

    LTREE_PATH_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/

    class << self
      def create!(model, attrs)
        attrs = attrs.symbolize_keys
        validate_path!(model, attrs[:path])
        model.create!(attrs)
      end

      # `attrs` may carry the immutable fields: a PATCH that restates a
      # slug unchanged is fine, one that changes it is refused. They are
      # never written either way.
      def update!(node, attrs)
        attrs    = attrs.symbolize_keys
        immutable = immutable_fields(node)
        changed   = immutable.select { |field| attrs.key?(field) && attrs[field].to_s != node[field].to_s }
        raise ImmutableField, changed if changed.any?

        node.update!(attrs.except(*immutable))
        node
      end

      # Row lock narrows the check-then-delete race (`dependent: :destroy`
      # would otherwise silently cascade a join added in between). A
      # concurrent INSERT can still slip past — admin-only path, accepted.
      def destroy!(node)
        node.with_lock do
          counts = references(node)
          raise InUse, counts if counts.values.any?(&:positive?)

          node.destroy!
        end
        node
      end

      def validate_path!(model, path)
        path = path.to_s
        raise InvalidPath, path unless path.match?(LTREE_PATH_FORMAT)

        parent = path.rpartition(".").first
        return if parent.blank? || model.exists?(path: parent)

        raise ParentMissing, parent
      end

      # Every place a node can still be referenced. A delete that ignored
      # these would drop a node out of somebody's avoid list — UserProfile
      # tolerates stale ids on read, so the filter would silently weaken
      # rather than fail loudly.
      def references(node)
        if node.is_a?(Tag)
          {
            # `<@` includes the node itself — exclude it.
            descendants: Tag.descendants_of(node.path).where.not(id: node.id).count,
            items:       ItemTag.where(tag_id: node.id).count,
            presets:     DietaryProfileTag.where(tag_id: node.id).count,
            modifiers:   ItemModifier.where("tag_ids @> ARRAY[:id]::uuid[]", id: node.id).count,
            profiles:    profiles_referencing(node)
          }
        else
          {
            descendants: Ingredient.descendants_of(node.path).where.not(id: node.id).count,
            items:       ItemIngredient.where(ingredient_id: node.id).count,
            presets:     DietaryProfileIngredient.where(ingredient_id: node.id).count,
            modifiers:   ItemModifier.where("ingredient_ids @> ARRAY[:id]::uuid[]", id: node.id).count,
            profiles:    profiles_referencing(node)
          }
        end
      end

      def immutable_fields(node)
        node.is_a?(Tag) ? %i[slug path family] : %i[slug path]
      end

      private

      # `prefer_tag_ids` counts, which is where the two doors used to
      # disagree. Nothing ranks by it today (docs/roadmap.md "Open
      # follow-ups"), but onboarding and PATCH /profile still write it and
      # the account export still hands it back, so it is a preference the
      # user set and can see. Deleting the tag out from under it is
      # unannounced data loss either way — and between two doors that must
      # agree, the answer to converge on is the one that refuses.
      #
      # The avoid arrays are GIN-indexed; the taste arrays aren't —
      # taxonomy deletes are rare enough that a seq scan is fine.
      def profiles_referencing(node)
        if node.is_a?(Tag)
          UserProfile.where(
            "avoid_tag_ids @> ARRAY[:id]::uuid[] OR " \
            "prefer_tag_ids @> ARRAY[:id]::uuid[] OR " \
            "liked_tag_ids @> ARRAY[:id]::uuid[] OR " \
            "disliked_tag_ids @> ARRAY[:id]::uuid[]",
            id: node.id
          ).count
        else
          UserProfile.where(
            "avoid_ingredient_ids @> ARRAY[:id]::uuid[] OR " \
            "liked_ingredient_ids @> ARRAY[:id]::uuid[] OR " \
            "disliked_ingredient_ids @> ARRAY[:id]::uuid[]",
            id: node.id
          ).count
        end
      end
    end
  end
end
