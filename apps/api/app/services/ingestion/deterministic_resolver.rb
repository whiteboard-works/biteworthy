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
    # false negative a gluten-free filter cannot afford. A keyword hit
    # in the dish's identity (name or section) unions the base into the
    # matches (source "derived" — inferred, not read off the menu) AND
    # routes the item to the model gap-fill, which can catch what this
    # table doesn't (sauces, broths, batters).
    #
    # `suppressed_by`: an explicit match under one of these subtrees
    # names an alternative base, so the wheat default yields
    # ("Quesadilla — corn tortilla" is corn, not wheat). The base's own
    # subtree always suppresses. Deliberately excluded keywords, because
    # their dominant menu use isn't wheat: "roll" (California Roll is
    # rice), "taco"/"tostada"/"sope" (corn tortilla by default),
    # "chip"/"nacho" (corn). `terms` is the plural-bridged form of
    # `keywords` (same idea as IngredientMatcher#singularize_last: menu
    # names are as often "Burgers" as "Burger").
    IMPLIED_BASE_RULES = [
      { slug: "grain-wheat",
        suppressed_by: [],
        keywords: %w[
          pizza pizzetta pizzeta pizzette calzone stromboli focaccia panini
          sandwich burger hamburger cheeseburger slider hoagie sub
          pasta spaghetti fettuccine linguine rigatoni macaroni ziti penne
          lasagna ravioli tortellini gnocchi
          bread toast crostini bruschetta flatbread naan pita cornbread bagel
          croissant biscuit pretzel pancake waffle crepe tempura
          dumpling gyoza potsticker wonton ramen udon
          cake pie tart brownie cookie donut churro
        ] + ["lo mein", "chow mein"] },
      # Flour-tortilla dishes: an explicit corn-flour base wins (plain
      # corn kernels live at grain.maize_corn and don't suppress).
      { slug: "grain-wheat",
        suppressed_by: %w[grain.corn],
        keywords: %w[wrap burrito quesadilla chimichanga] },
      # Generic noodles: rice/buckwheat noodles are named as such (ramen,
      # udon, lo/chow mein are wheat by definition — unsuppressed above).
      { slug: "grain-wheat",
        suppressed_by: %w[grain.rice grain.buckwheat],
        keywords: %w[noodle] }
    ].map do |rule|
      terms = rule[:keywords].flat_map do |kw|
        words = kw.split(" ")
        [kw, (words[0..-2] + [words[-1].pluralize]).join(" ")]
      end
      rule.merge(terms: terms.uniq.freeze).freeze
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
        section_segments  = MenuText.segments(item.section_name)
        identity_segments = MenuText.segments(item.name) + section_segments
        hit_rules = implied_base_hits(identity_segments)
        matches += implied_rows(hit_rules, matches, identity_segments)

        tags = TagDeriver.derive(
          segments:             MenuText.segments(item.name, item.description),
          section_segments:     section_segments,
          resolved_ingredients: matches
        )

        Result.new(
          item_id:     item.id,
          ingredients: matches.map { |m| payload_row(m) },
          tags:        tags.map { |t| payload_row(t) },
          gap_phrases: gap_phrases,
          gap:         gap?(matches, gap_phrases, hit_rules)
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
    def gap?(matches, gap_phrases, hit_rules)
      hit_rules.any? ||
        matches.empty? ||
        gap_phrases.any? ||
        matches.any? { |m| TagDeriver.under_any?(m[:path].to_s, %w[condiment]) }
    end

    # Scans the dish's identity — name plus section, because a "Pizzas"
    # section implies crust for every "Margherita" in it. Descriptions
    # are deliberately out: they state ingredients, the matcher's job.
    def implied_base_hits(identity_segments)
      IMPLIED_BASE_RULES.select do |rule|
        TagDeriver.keyword_hits(identity_segments, { rule[:slug] => rule[:terms] },
                                confidence: IMPLIED_BASE_CONFIDENCE).any?
      end
    end

    # Union rows for hit rules whose slug is in the catalog, unless an
    # explicit match already covers the base's own subtree ("Quesadilla —
    # flour tortilla" needs no extra wheat row) or a suppressing
    # alternative base ("Quesadilla — corn tortilla" is corn, not
    # wheat), or the dish's identity claims a diet the base would
    # contradict. Every hit still routes the item to gap-fill.
    def implied_rows(hit_rules, matches, identity_segments)
      return [] if hit_rules.empty?

      claims = TagDeriver.keyword_hits(identity_segments, TagDeriver::Diet::KEYWORDS, confidence: 0)
                         .map { |c| c[:slug] }
      hit_rules.filter_map do |rule|
        path = @matcher.path_for(rule[:slug])
        next if path.nil?
        next if matches.any? { |m| TagDeriver.under_any?(m[:path].to_s, [path] + rule[:suppressed_by]) }

        row = { slug: rule[:slug], path: path, confidence: IMPLIED_BASE_CONFIDENCE, source: "derived" }
        next if contradicts_diet_claim?(row, claims)

        row
      end.uniq
    end

    # A dish whose own identity claims a diet must not gain a base that
    # contradicts the claim: unioning wheat into "Gluten-Free Pizza"
    # would derive contains-gluten, veto the claim itself
    # (TagDeriver::Diet::CONTRADICTED_BY), and hide the dish from
    # exactly the users it exists for. Claims are read from name/section
    # only — a description's "gluten-free crust available" usually marks
    # an optional variant, and defaulting the base in (hiding the dish)
    # is the safe direction there.
    def contradicts_diet_claim?(row, claims)
      return false if claims.empty?

      allergens = TagDeriver::Allergen.call(resolved_ingredients: [row]).map { |t| t[:slug] }
      claims.any? { |claim| Array(TagDeriver::Diet::CONTRADICTED_BY[claim]).intersect?(allergens) }
    end

    def payload_row(row)
      AssociationPayload.load(row).dump
    end
  end
end
