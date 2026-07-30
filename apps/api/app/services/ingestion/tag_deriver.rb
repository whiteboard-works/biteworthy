# frozen_string_literal: true

module Ingestion
  # Programmatic tag resolution, one strategy per tag family so each can
  # be tuned (or fail) independently:
  #
  #   allergen — derived from resolved ingredients' ltree ancestry; the
  #              ONLY code path that emits allergen tags (the LLM is
  #              never asked for them).
  #   diet     — explicit menu claims ("vegan", "gluten free") with an
  #              ingredient-ancestry veto; never inferred from absence.
  #   prep     — keyword table (fried/grilled/smoked/raw).
  #   flavor   — keyword table (spicy/sweet).
  #   cuisine  — weak keyword pass (incl. section name); the LLM
  #              gap-fill owns this family's real coverage.
  #
  # All slugs referenced here must exist in db/seeds/tags.yml /
  # ingredients.yml — spec/services/ingestion/taxonomy_drift_spec.rb
  # fails CI when the taxonomy moves out from under these tables.
  #
  # Context keys: segments (name+description token arrays from
  # MenuText.segments), section_segments, and resolved_ingredients as
  # [{slug:, path:, confidence:, source:}].
  class TagDeriver
    def self.derive(segments:, resolved_ingredients:, section_segments: [])
      ctx = { segments:, section_segments:, resolved_ingredients: }
      FAMILY_STRATEGIES.flat_map do |family, strategy|
        strategy.call(ctx)
      rescue StandardError => e
        Rails.logger.error("TagDeriver: #{family} strategy failed: #{e.class} #{e.message}")
        []
      end
    end

    # Whole-phrase keyword lookup: does the keyword's token sequence
    # appear contiguously in any segment?
    def self.keyword_hits(segments, table, confidence:)
      table.filter_map do |tag_slug, keywords|
        found = keywords.any? do |kw|
          kw_tokens = kw.split(" ")
          segments.any? { |tokens| tokens.each_cons(kw_tokens.length).include?(kw_tokens) }
        end
        { slug: tag_slug, confidence:, source: "match" } if found
      end
    end

    def self.under_any?(path, prefixes)
      prefixes.any? { |p| path == p || path.start_with?("#{p}.") }
    end

    module Allergen
      # Ingredient subtree → allergen tag. Prefix-tested against the
      # ltree paths already in memory from the matcher — no SQL.
      SUBTREE_TAGS = {
        "dairy"            => "contains-dairy",
        "egg"              => "contains-egg",
        "fish"             => "contains-fish",
        "shellfish"        => "contains-shellfish",
        "soy"              => "contains-soy",
        "sesame"           => "contains-sesame",
        "tree_nut"         => "contains-tree-nut",
        "legume.peanuts"   => "contains-peanut",
        "grain.wheat"      => "contains-gluten",
        "grain.barley"     => "contains-gluten",
        "grain.rye"        => "contains-gluten",
        "grain.spelt"      => "contains-gluten",
        "grain.triticale"  => "contains-gluten"
      }.freeze

      # Cross-root oddballs the subtree map can't see. Coconut counts as
      # a tree nut per FDA labeling guidance.
      SLUG_TAGS = {
        "condiment-oyster-sauce"        => %w[contains-shellfish],
        "oil-and-fat-toasted-sesame-oil" => %w[contains-sesame],
        "fruit-coconut"                 => %w[contains-tree-nut],
        "fruit-coconut-milk"            => %w[contains-tree-nut],
        "fruit-coconut-yogurt"          => %w[contains-tree-nut],
        "oil_and_fat-coconut-oil"       => %w[contains-tree-nut],
        "condiment-coconut-water"       => %w[contains-tree-nut],
        "sweetener-coconut-sugar"       => %w[contains-tree-nut],
        "grain-rice-coconut-rice"       => %w[contains-tree-nut]
      }.freeze

      def self.call(ctx)
        best = {}
        ctx[:resolved_ingredients].each do |ing|
          tag_slugs = Array(SLUG_TAGS[ing[:slug]]) +
                      SUBTREE_TAGS.filter_map { |prefix, tag| tag if TagDeriver.under_any?(ing[:path].to_s, [prefix]) }
          source = ing[:source] == "ai" ? "ai" : "derived"
          tag_slugs.uniq.each do |tag_slug|
            row = { slug: tag_slug, confidence: ing[:confidence], source: }
            best[tag_slug] = row if best[tag_slug].nil? || row[:confidence] > best[tag_slug][:confidence]
          end
        end
        best.values
      end
    end

    module Diet
      KEYWORDS = {
        "vegan"        => ["vegan"],
        "vegetarian"   => %w[vegetarian veggie],
        "gluten-free"  => ["gluten free", "gf"],
        "dairy-free"   => ["dairy free"],
        "nut-free"     => ["nut free"],
        "keto"         => ["keto"],
        "paleo"        => ["paleo"],
        "halal"        => ["halal"],
        "kosher"       => ["kosher"],
        "pescatarian"  => ["pescatarian"]
      }.freeze

      # Resolved ingredients veto contradicted claims — menu keywords
      # usually mark a variant option ("vegan available", "GF option"),
      # and a false diet claim is the dangerous direction for our users.
      ANIMAL_PREFIXES     = %w[meat poultry fish shellfish].freeze
      VEGAN_ONLY_PREFIXES = %w[dairy egg].freeze

      # Diet claim → allergen tags (from this item's Allergen derivation)
      # that make it a lie. Riding on Allergen keeps the gluten subtrees
      # and cross-root oddballs (coconut → tree nut) in one place.
      CONTRADICTED_BY = {
        "gluten-free" => %w[contains-gluten],
        "dairy-free"  => %w[contains-dairy],
        "nut-free"    => %w[contains-tree-nut contains-peanut]
      }.freeze

      def self.call(ctx)
        hits = TagDeriver.keyword_hits(ctx[:segments], KEYWORDS, confidence: 0.9)
        return hits if hits.empty?

        paths = ctx[:resolved_ingredients].map { |i| i[:path].to_s }
        animal = paths.any? { |p| TagDeriver.under_any?(p, ANIMAL_PREFIXES) }
        animal_product = animal || paths.any? { |p| TagDeriver.under_any?(p, VEGAN_ONLY_PREFIXES) }
        allergens = Allergen.call(ctx).map { |t| t[:slug] }

        hits.reject do |h|
          (h[:slug] == "vegetarian" && animal) ||
            (h[:slug] == "vegan" && animal_product) ||
            Array(CONTRADICTED_BY[h[:slug]]).intersect?(allergens)
        end
      end
    end

    module Prep
      KEYWORDS = {
        "fried"   => ["fried", "deep fried"],
        "grilled" => ["grilled", "char grilled", "charbroiled"],
        "smoked"  => ["smoked", "house smoked"],
        "raw"     => ["raw"]
      }.freeze

      def self.call(ctx) = TagDeriver.keyword_hits(ctx[:segments], KEYWORDS, confidence: 0.9)
    end

    module Flavor
      KEYWORDS = {
        "spicy" => ["spicy"],
        "sweet" => ["sweet"]
      }.freeze

      def self.call(ctx) = TagDeriver.keyword_hits(ctx[:segments], KEYWORDS, confidence: 0.85)
    end

    module Cuisine
      KEYWORDS = {
        "italian"  => ["italian"],
        "mexican"  => ["mexican"],
        "thai"     => ["thai"],
        "japanese" => ["japanese"],
        "indian"   => ["indian"],
        "american" => ["american"]
      }.freeze

      def self.call(ctx)
        TagDeriver.keyword_hits(ctx[:segments] + ctx[:section_segments], KEYWORDS, confidence: 0.9)
      end
    end

    FAMILY_STRATEGIES = {
      "allergen" => Allergen,
      "diet"     => Diet,
      "prep"     => Prep,
      "flavor"   => Flavor,
      "cuisine"  => Cuisine
    }.freeze
  end
end
