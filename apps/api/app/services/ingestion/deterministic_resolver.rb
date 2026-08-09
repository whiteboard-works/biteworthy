# frozen_string_literal: true

module Ingestion
  # Orchestrates the code-side resolve pass over a run's materialized
  # IngestionItems: explicit-mention ingredient matching + per-family
  # tag derivation, and the gap decision — which items still deserve the
  # (single, background) LLM gap-fill call.
  #
  # Stateless on purpose: GapFillResolveJob re-runs this to recompute
  # the identical gap set instead of trusting anything persisted.
  class DeterministicResolver
    Result = Data.define(:item_id, :ingredients, :tags, :gap_phrases, :gap) do
      def gap? = gap
    end

    def self.call(items, matcher: IngredientMatcher.new)
      new(matcher:).call(items)
    end

    def initialize(matcher: IngredientMatcher.new)
      @matcher = matcher
    end

    def call(items)
      items.map do |item|
        matches, gap_phrases = match_item(item)

        tags = TagDeriver.derive(
          segments:             MenuText.segments(item.name, item.description),
          section_segments:     MenuText.segments(item.section_name),
          resolved_ingredients: matches
        )

        Result.new(
          item_id:     item.id,
          ingredients: matches.map { |m| payload_row(m) },
          tags:        tags.map { |t| payload_row(t) },
          gap_phrases: gap_phrases,
          gap:         gap?(matches, gap_phrases)
        )
      end
    end

    private

    # The description is the ingredient authority: its leftovers always
    # look like unknown ingredients. Dish-name leftovers usually aren't
    # ("Taco", "Bowl") — they only count when the name is all the
    # evidence we have (no description, or one that matched nothing).
    def match_item(item)
      name_matches, name_leftovers = @matcher.scan(item.name)
      desc_matches, desc_leftovers = @matcher.scan(item.description)

      gap_phrases = desc_leftovers.dup
      gap_phrases += name_leftovers if item.description.blank? || desc_matches.empty?

      [merge_matches(name_matches, desc_matches), gap_phrases]
    end

    def merge_matches(*match_lists)
      match_lists.flatten
                 .group_by { |m| m[:slug] }
                 .map { |_, rows| rows.max_by { |r| r[:confidence] } }
    end

    # An item goes to gap-fill when explicit matching can't be the whole
    # story: nothing matched at all, leftover phrases look like unknown
    # ingredients, or a matched ingredient is a composite condiment
    # ("caesar dressing" resolves, but still hides anchovy/egg/dairy).
    def gap?(matches, gap_phrases)
      matches.empty? ||
        gap_phrases.any? ||
        matches.any? { |m| TagDeriver.under_any?(m[:path].to_s, %w[condiment]) }
    end

    def payload_row(row)
      AssociationPayload.load(row).dump
    end
  end
end
