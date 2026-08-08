# frozen_string_literal: true

module Menus
  # Avoiding a node means avoiding everything under it.
  #
  # The taxonomy is hierarchical for a reason — `dairy` has 90 descendants,
  # `dairy.cheddar` among them — but the filter compares id arrays, so a
  # person who said "I avoid dairy" was shown a Cheese Quesadilla tagged
  # `dairy-cheddar` as visible. That is the product's entire safety claim
  # failing in the most ordinary case there is: the parent node is
  # `allergen: true`, it is what `search_taxonomy` returns for "dairy", and
  # it is what anyone would pick.
  #
  # Resolution happens here, before the filter runs, rather than inside it:
  #
  #   * **What the person chose stays what they chose.** The stored list is
  #     one id, so the UI shows "dairy" instead of ninety cheeses and
  #     removing it is one operation rather than ninety.
  #   * **The filter algorithm is untouched**, which is what keeps it
  #     honest against `packages/filter-engine`. That mirror takes an
  #     already-resolved avoid set; expansion is the caller's job on both
  #     sides, so the two implementations still compare like for like.
  #
  # Presets are stored pre-expanded (vegan carries 328 ingredient ids) —
  # which is exactly the workaround that proves the filter never did this
  # itself. Re-expanding them is a no-op.
  module Subtree
    class << self
      def ingredient_ids(ids) = expand(Ingredient, ids)
      def tag_ids(ids)        = expand(Tag, ids)

      private

      # One query per taxonomy. `path <@ ANY(...)` is an indexed ltree
      # containment check, so this stays a single index scan rather than a
      # query per avoided node.
      def expand(model, ids)
        ids = Array(ids).compact.uniq
        return ids if ids.empty?

        paths = model.where(id: ids).pluck(:path).compact
        return ids if paths.empty?

        (ids + model.where("path <@ ANY (ARRAY[:paths]::ltree[])", paths: paths).pluck(:id)).uniq
      end
    end
  end
end
