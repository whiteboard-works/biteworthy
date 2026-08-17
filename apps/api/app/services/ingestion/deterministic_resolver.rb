# frozen_string_literal: true

module Ingestion
  # Orchestrates the code-side resolve pass over a run's materialized
  # IngestionItems: explicit-mention ingredient matching, implied
  # composed-dish bases, per-family tag derivation, and the gap
  # decision — which items still deserve the background LLM gap-fill.
  #
  # Stateless on purpose: GapFillResolveJob re-runs this to recompute
  # the identical gap set instead of trusting anything persisted.
  class DeterministicResolver
    Result = Data.define(:item_id, :ingredients, :tags, :gap_phrases, :gap) do
      def gap? = gap
    end

    # Composed-dish names imply a base ingredient the description never
    # states: a "Margherita — tomato sauce, mozzarella, basil" that
    # cleanly resolves still has a wheat crust, which is exactly the
    # false negative a gluten-free filter cannot afford. A name-keyword
    # hit unions the base into the matches (source "derived" — inferred,
    # not read off the menu) AND routes the item to the model gap-fill,
    # which can catch what this table doesn't (sauces, broths, batters).
    IMPLIED_BASE_KEYWORDS = {
      "grain-wheat" => %w[
        pizza pizzette sandwich burger hamburger cheeseburger slider hoagie sub
        wrap burrito quesadilla chimichanga
        pasta spaghetti fettuccine penne lasagna ravioli gnocchi
        bread toast crostini bruschetta flatbread naan pita cornbread tempura
        dumpling gyoza potsticker wonton noodle ramen udon
        cake pie tart brownie cookie donut churro
      ] + ["lo mein", "chow mein"]
    }.freeze

    # Plural bridge, same idea as IngredientMatcher#singularize_last:
    # menu names are as often "Burgers" as "Burger".
    IMPLIED_BASE_TERMS = IMPLIED_BASE_KEYWORDS.transform_values do |keywords|
      keywords.flat_map do |kw|
        words = kw.split(" ")
        [kw, (words[0..-2] + [words[-1].pluralize]).join(" ")]
      end.uniq
    end.freeze

    IMPLIED_BASE_CONFIDENCE = 0.8

    def self.call(items, matcher: IngredientMatcher.new)
      new(matcher:).call(items)
    end

    def initialize(matcher: IngredientMatcher.new)
      @matcher = matcher
    end

    def call(items)
      items.map do |item|
        matches, gap_phrases = match_item(item)
        implied_hits = implied_base_hits(item)
        matches += implied_rows(implied_hits, matches)

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
          gap:         gap?(matches, gap_phrases, implied_hits)
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
    # ingredients, a matched ingredient is a composite condiment
    # ("caesar dressing" resolves, but still hides anchovy/egg/dairy),
    # or the name marks a composed dish — even a cleanly-resolved pizza
    # hides more than its listed toppings.
    def gap?(matches, gap_phrases, implied_hits)
      implied_hits.any? ||
        matches.empty? ||
        gap_phrases.any? ||
        matches.any? { |m| TagDeriver.under_any?(m[:path].to_s, %w[condiment]) }
    end

    # Name-only on purpose: descriptions state ingredients (the matcher's
    # job); it's the dish-name vocabulary that implies unstated bases.
    def implied_base_hits(item)
      TagDeriver.keyword_hits(MenuText.segments(item.name), IMPLIED_BASE_TERMS,
                              confidence: IMPLIED_BASE_CONFIDENCE)
    end

    # Union rows for hits whose slug is in the catalog and whose subtree
    # isn't already matched explicitly ("Quesadilla — flour tortilla"
    # needs no extra grain-wheat row; the item still gap-fills).
    def implied_rows(hits, matches)
      hits.filter_map do |hit|
        path = @matcher.path_for(hit[:slug])
        next if path.nil?
        next if matches.any? { |m| TagDeriver.under_any?(m[:path].to_s, [path]) }

        { slug: hit[:slug], path: path, confidence: hit[:confidence], source: "derived" }
      end
    end

    def payload_row(row)
      AssociationPayload.load(row).dump
    end
  end
end
