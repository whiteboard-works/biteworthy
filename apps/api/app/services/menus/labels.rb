# frozen_string_literal: true

module Menus
  # Bulk-loads the display names a menu response can cite, keyed by id so
  # Filter#reasons_for is a hash lookup rather than a query per reason.
  #
  # Ingredient "family" is the first ltree segment (`dairy.cheddar` →
  # `dairy`); tags carry family as a column.
  module Labels
    EMPTY = { ingredients: {}, tags: {} }.freeze

    class << self
      # Only ids the filter could actually cite — the intersection of what
      # the items carry and what the caller avoids.
      def for_filter(items, filter)
        cited_ingredient_ids = items.flat_map(&:denormalized_ingredient_ids).uniq & filter.avoid_ingredient_ids
        cited_tag_ids        = items.flat_map(&:denormalized_tag_ids).uniq        & filter.avoid_tag_ids

        build(ingredient_ids: cited_ingredient_ids, tag_ids: cited_tag_ids)
      end

      # Names for the matched liked ids so taste_reasons renders the
      # "because you like…" line without a second roundtrip.
      def for_taste(scores)
        return EMPTY if scores.nil?

        build(
          ingredient_ids: scores.values.flat_map { |s| s[:matched_liked_ingredient_ids] }.uniq,
          tag_ids:        scores.values.flat_map { |s| s[:matched_liked_tag_ids] }.uniq
        )
      end

      private

      def build(ingredient_ids:, tag_ids:)
        {
          ingredients: Ingredient.where(id: ingredient_ids)
                                 .pluck(:id, :name, :path)
                                 .to_h { |id, name, path| [id, { name: name, family: path.to_s.split(".").first }] },
          tags:        Tag.where(id: tag_ids)
                          .pluck(:id, :name, :family)
                          .to_h { |id, name, family| [id, { name: name, family: family }] }
        }
      end
    end
  end
end
