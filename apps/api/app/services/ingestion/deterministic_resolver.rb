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
    # states: a "Margherita Pizza — tomato sauce, mozzarella, basil"
    # that cleanly resolves still has a wheat crust, which is exactly
    # the false negative a gluten-free filter cannot afford. A keyword
    # hit in the item NAME unions the base into the matches (source
    # "derived" — inferred, not read off the menu) AND routes the item
    # to the model gap-fill, which can catch what this table doesn't
    # (sauces, broths, batters).
    #
    # Deliberately dumb, and deliberately name-only. Earlier revisions
    # scanned section names for the union and carried per-keyword
    # suppressor subtrees ("an explicit corn match suppresses a
    # quesadilla's wheat"); probing them against the real catalog showed
    # each increment of cleverness inverting somewhere (a "Tacos &
    # Burritos" section adding wheat to corn tacos; corn grits killing a
    # burrito's flour tortilla). Dish semantics are genuinely ambiguous,
    # and that judgment belongs to the model pass + human verify
    # (working rule 5), so the table keeps only the direction that can't
    # silently harm: a corn-tortilla quesadilla gains a wrong derived
    # wheat row, which surfaces as hidden-with-reason + show-anyway + a
    # human-fixable card — recoverable; a silent pass on a wheat crust
    # is not. The one guard is DietClaims: a name's own diet claim
    # ("Gluten-Free Pizza") beats name-derived inference.
    #
    # Keywords whose pluralize is identity (the -ta/-ia Latin-plural
    # inflector rule: pasta, pizzetta, focaccia, bruschetta, pita) carry
    # their plural forms explicitly. Deliberately excluded, because
    # their dominant menu use isn't wheat: "roll" (California Roll is
    # rice), "taco"/"tostada"/"sope" (corn tortilla by default),
    # "chip"/"nacho" (corn).
    IMPLIED_BASE_KEYWORDS = {
      "grain-wheat" => %w[
        pizza pizzetta pizzeta pizzette pizzettas pizzetas
        calzone stromboli focaccia focaccias focacce panini
        sandwich burger hamburger cheeseburger slider hoagie sub
        wrap burrito quesadilla chimichanga
        pasta pastas spaghetti fettuccine linguine rigatoni macaroni ziti
        penne lasagna ravioli tortellini gnocchi
        bread toast crostini bruschetta bruschettas bruschette flatbread
        naan pita pitas cornbread bagel croissant biscuit pretzel
        pancake waffle crepe tempura
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
        name_claims = DietClaims.claims_in(MenuText.segments(item.name))
        matches, gap_phrases = match_item(item, name_claims)
        name_hits = implied_base_hits(MenuText.segments(item.name))
        matches += implied_rows(name_hits, matches, name_claims)

        section_segments = MenuText.segments(item.section_name)
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
          # Section keywords route but never union: a "Pizzas" section
          # is a strong hint the model should look at every item in it,
          # and a terrible reason for code to assert wheat (a "Tacos &
          # Burritos" section would wheat a corn taco). The gap-fill
          # prompt carries the section name, so the judgment lands where
          # it belongs.
          gap:         gap?(matches, gap_phrases, name_hits + implied_base_hits(section_segments))
        )
      end
    end

    private

    # The description is the ingredient authority: its leftovers always
    # look like unknown ingredients. Dish-name leftovers usually aren't
    # ("Taco", "Bowl") — they only count when the name is all the
    # evidence we have (no description, or one that matched nothing).
    def match_item(item, name_claims)
      name_matches, name_leftovers = @matcher.scan(item.name)
      # The name's claim beats the name's own evidence ("pasta" matching
      # the catalog inside "Gluten-Free Pasta"); description matches are
      # exempt — a dish that lists wheat flour is not gluten-free
      # whatever its name says.
      name_matches = name_matches.reject do |m|
        DietClaims.contradicted?(name_claims, slug: m[:slug], path: m[:path])
      end
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
    # or the name or section marks a composed dish — even a
    # cleanly-resolved pizza hides more than its listed toppings.
    def gap?(matches, gap_phrases, implied_hits)
      implied_hits.any? ||
        matches.empty? ||
        gap_phrases.any? ||
        matches.any? { |m| TagDeriver.under_any?(m[:path].to_s, %w[condiment]) }
    end

    def implied_base_hits(segments)
      TagDeriver.keyword_hits(segments, IMPLIED_BASE_TERMS, confidence: IMPLIED_BASE_CONFIDENCE)
    end

    # Union rows for hits whose slug is in the catalog, unless an
    # explicit match already covers the base's own subtree ("Quesadilla —
    # flour tortilla" needs no extra wheat row) or the name's diet claim
    # contradicts the base. Every hit still routes the item to gap-fill.
    def implied_rows(hits, matches, name_claims)
      hits.filter_map do |hit|
        path = @matcher.path_for(hit[:slug])
        next if path.nil?
        next if matches.any? { |m| TagDeriver.under_any?(m[:path].to_s, [path]) }
        next if DietClaims.contradicted?(name_claims, slug: hit[:slug], path: path)

        { slug: hit[:slug], path: path, confidence: hit[:confidence], source: "derived" }
      end.uniq
    end

    def payload_row(row)
      AssociationPayload.load(row).dump
    end
  end
end
