# frozen_string_literal: true

module Ingestion
  # Prompt for the single background enrichment call that follows the
  # deterministic resolve. The model only sees items the code flagged as
  # gaps, and is only asked for what code can't do: implied ingredients
  # and cuisine tags. Allergen/diet/prep/flavor never come from here —
  # TagDeriver re-derives them over the merged ingredient set.
  class GapFillPrompt
    SYSTEM_INSTRUCTIONS = <<~MD.strip
      You are the second-pass enricher for a menu ingestion pipeline. A
      deterministic matcher already resolved every explicitly named
      ingredient (the item's `matched` list). Your job is only what
      code cannot do.

      For each item I send, return:
        * `ingredients.resolved`: ADDITIONAL ingredient slugs implied by
          the dish but not explicitly named ("Caesar Salad" implies
          anchovy, parmesan, egg), each with a confidence (0..1).
        * `ingredients.unresolved`: strings from `unmatched` that are
          real ingredients missing from the catalog (raw material for
          the curation queue).
        * `cuisine_tags.resolved`: cuisine tag slugs for the item from
          the cuisine catalog, each with a confidence (0..1).
        * `cuisine_tags.unresolved`: cuisine-ish phrases not in the
          catalog.

      Rules:
        * Use slugs **verbatim** from the catalogs — no fuzzy matches,
          no inventing.
        * Never repeat a slug from the item's `matched` list.
        * `index` in the response must equal the index I gave you.
        * Items in the response must appear in the same order as the input.
        * Output JSON only. No prose, no markdown fences.
    MD

    class << self
      # Instructions + both catalogs, one cache breakpoint on the last
      # block so the whole (stable) prefix is cached across runs.
      def system(client)
        client.system_blocks(
          { text: SYSTEM_INSTRUCTIONS },
          { text: "# Ingredient catalog\n#{CatalogBuilder.ingredients_text}" },
          { text: "# Cuisine tag catalog\n#{CatalogBuilder.tags_text(family: 'cuisine')}", cache: true }
        )
      end

      # `items` rows: {name:, description:, section:, matched: [slugs],
      # unmatched: [phrases]}.
      def user_messages(items)
        [{
          role: "user",
          content: [
            { type: "text", text: "Enrich the following items:\n\n#{items_block(items)}" }
          ]
        }]
      end

      def items_block(items)
        items.each_with_index.map do |item, i|
          line = "[#{i}] #{item[:name]}"
          line += " (section: #{item[:section]})" if item[:section].present?
          line += "\n    description: #{item[:description]}" if item[:description].present?
          line += "\n    matched: #{item[:matched].join(', ')}" if item[:matched].present?
          line += "\n    unmatched: #{item[:unmatched].join(', ')}" if item[:unmatched].present?
          line
        end.join("\n")
      end
    end
  end
end
