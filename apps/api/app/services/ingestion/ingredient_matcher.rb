# frozen_string_literal: true

module Ingestion
  # Deterministic ingredient resolution: matches explicit mentions in a
  # menu item's name/description against the ingredient catalog's names
  # and aliases[]. Builds one in-memory index per instance (1.1k rows),
  # so a whole run resolves with a single SELECT and zero LLM calls.
  #
  # Matching is precision-first: exact normalized phrase lookups only,
  # longest phrase wins ("goat cheese" never also matches "cheese"), and
  # a plural/singular bridge via last-word singularization on both the
  # index terms and the scanned text. No trigram/fuzzy layer — for an
  # allergy product a wrong match is worse than a miss, and misses are
  # exactly what the LLM gap-fill pass (plus human verify) exists for.
  # (Future option: a batched pg_trgm similarity() sweep over leftover
  # phrases feeding the curation queue only, never payloads.)
  class IngredientMatcher
    NAME_CONFIDENCE  = 1.0
    ALIAS_CONFIDENCE = 0.95

    # Non-ingredient menu vocabulary that shouldn't survive into gap
    # phrases: filler, portioning, and cooking-method words (those carry
    # prep-tag signal, but TagDeriver reads them from the raw segments —
    # here they'd only masquerade as unknown ingredients). Leftover runs
    # are edge-trimmed against this list (interior words are kept so
    # multi-word unknowns like "pico de gallo" stay intact).
    STOPWORDS = %w[
      a an the of in on to for from our your all each per plus
      served choice topped fresh house made homemade side add extra
      style drizzled finished comes daily local seasonal organic
      small medium large half whole double
      grilled fried deep baked roasted sauteed seared steamed braised
      smoked charbroiled crispy breaded battered toasted blackened
      glazed marinated stuffed shredded sliced diced chopped minced
      melted warm cold
    ].freeze

    # Phrases that name the ABSENCE of an ingredient. "Dairy" is the root
    # node's own name and "cheese" its alias, so without this "dairy-free
    # dressing" and "vegan cheese" matched dairy and a vegan dish lost its
    # vegan tag. They are consumed as leftovers, so gap-fill and the
    # reviewer still see them (a vegan cheese is often cashew or soy).
    ABSENCE_PHRASES = [
      "dairy free", "non dairy", "cheese free", "no cheese", "without cheese",
      "vegan cheese", "plant based cheese", "dairy free cheese", "non dairy cheese",
      "vegan parmesan", "vegan mozzarella", "vegan butter", "vegan mayo",
      "nut free", "tree nut free", "peanut free", "no nuts", "without nuts"
    ].freeze

    NEGATIONS = %w[not isnt nor].freeze
    # "isn't" normalizes to the tokens "isn" "t".
    CONTRACTION_STEMS = %w[isn aren wasn doesn don].freeze
    # "dairy-free option available" offers a variant; the dish as served
    # still has the ingredient.
    # Only the words that mark a variant on offer: "vegan butter
    # substitute" or "alternative" names the dairy-free ingredient itself.
    ALTERNATIVE_WORDS = %w[option options available upon request].freeze
    # The same offer phrased before the claim ("can be made peanut-free",
    # "optionally gluten free"). Whole phrases ending right at the claim:
    # a lone "made" is composition ("made with dairy-free cheese").
    VARIANT_LEADS = [ "can be made", "can be", "can make", "ask for", "optionally", "optional" ].freeze
    # Longest VARIANT_LEAD is three tokens. Carried across MenuText
    # segment boundaries so "can be made: peanut-free" still sees the
    # offer — punctuation splits the lead and the claim apart.
    VARIANT_LEAD_WIDTH = VARIANT_LEADS.map { |v| v.split.size }.max

    Match = Data.define(:slug, :path, :confidence, :kind)

    # "Spring rolls" and "rice paper" are independent catalog hits in
    # different spans ("fresh spring rolls wrapped in rice paper"). The
    # rice paper is the qualified wrapper, so the generic wheat spring
    # roll in that same clause drops. A wheat spring-roll in another
    # clause ("crispy spring rolls with summer rolls wrapped in rice
    # paper") stays — dropping it under-hides gluten. Longest-phrase
    # matching already prefers "rice noodles" / "glass noodles" over the
    # "noodles" alias of wheat pasta; do not also drop a wheat-pasta hit
    # that co-occurs as its own ingredient ("pasta and rice noodles").
    WHEAT_SPRING_ROLL_SLUG = "grain-wheat-spring-roll"
    RICE_PAPER_PREFIX = "grain.rice.paper"

    def self.under_prefix?(path, prefix)
      path == prefix || path.start_with?("#{prefix}.")
    end

    def self.row_slug(row) = (row[:slug] || row["slug"]).to_s
    def self.row_path(row) = (row[:path] || row["path"]).to_s
    def self.row_clause(row) = row[:clause_id] || row["clause_id"]

    def self.prefer_qualified(rows)
      list = Array(rows)
      return list if list.empty?

      rice_paper_clauses = list.filter_map do |row|
        next unless under_prefix?(row_path(row), RICE_PAPER_PREFIX)

        row_clause(row)
      end.to_set
      return list if rice_paper_clauses.empty?

      list.reject do |row|
        next false unless row_slug(row) == WHEAT_SPRING_ROLL_SLUG

        # No clause_id means we cannot tell this wheat row came from the
        # same phrase as the rice paper. Keep it — the unsafe direction
        # is dropping an independent wheat spring-roll.
        clause = row_clause(row)
        clause && rice_paper_clauses.include?(clause)
      end
    end

    def self.payload_row(row)
      row.except(:clause_id, "clause_id")
    end

    def self.best_by_slug(rows)
      Array(rows)
        .group_by { |row| row_slug(row) }
        .map { |_, group| group.max_by { |row| row[:confidence] || row["confidence"] } }
    end

    def initialize(ingredients = Ingredient.pluck(:slug, :name, :path, :aliases))
      @index = {}
      @paths_by_slug = {}
      ingredients.each do |slug, name, path, aliases|
        @paths_by_slug[slug] = path.to_s
        add_term(name, slug:, path: path.to_s, kind: :name)
        Array(aliases).each { |a| add_term(a, slug:, path: path.to_s, kind: :alias) }
      end
      @max_ngram = (@index.keys + ABSENCE_PHRASES).map { |k| k.count(" ") + 1 }.max
    end

    # Scan one text; returns [matches, leftovers] where matches is an
    # array of {slug:, path:, confidence:, source:} hashes (deduped by
    # slug, best confidence kept) and leftovers the unmatched text runs
    # that could be ingredients we don't know. The caller decides how
    # name vs description leftovers weigh (see DeterministicResolver).
    def scan(text)
      hits, leftovers, = scan_hits(text)
      rows = self.class.best_by_slug(self.class.prefer_qualified(hits)).map { |row| self.class.payload_row(row) }
      [rows, leftovers]
    end

    # Same as scan, but leaves clause_id on each hit and does not
    # prefer_qualified / slug-dedupe. DeterministicResolver merges name
    # and description hits in one clause stream so "Fresh Spring Rolls"
    # / "wrapped in rice paper" still drop wheat, while a later clause
    # keeps an independent wheat spring-roll.
    def scan_hits(text, clause_id: 0)
      hits      = []
      leftovers = []
      prefix    = []
      last_clause = clause_id

      MenuText.segments(text).each_with_index do |tokens, seg_i|
        last_clause += 1 if seg_i.positive?
        last_clause = scan_segment(tokens, hits, leftovers, clause_id: last_clause, prefix: prefix)
        prefix = tokens.last(VARIANT_LEAD_WIDTH)
      end

      [hits, leftovers, last_clause]
    end

    # Catalog lookup by slug (nil when absent) — lets the resolver's
    # implied-bases pass place a known slug in the tree without a second
    # SELECT or a hand-rolled catalog.
    def path_for(slug) = @paths_by_slug[slug]

    private

    # Greedy longest-match-first n-gram scan. A hit consumes its tokens;
    # unmatched tokens accumulate into leftover runs. clause_id counts
    # connective breaks before the hit so prefer_qualified can correlate
    # rice paper with the spring-roll phrase it wraps, not a sibling dish.
    def scan_segment(tokens, hits, leftovers, clause_id:, prefix: [])
      run = []
      i = 0
      last_clause = clause_id
      while i < tokens.length
        extra = tokens[0...i].count { |token| MenuText::SEGMENT_BREAK_WORDS.include?(token) }
        this_clause = clause_id + extra
        last_clause = this_clause if this_clause > last_clause

        hit, width = longest_match_at(tokens, i, prefix: prefix)
        if hit == :absence
          run.concat(tokens[i, width])
          i += width
        elsif hit
          flush_leftover(run, leftovers)
          hits << { slug: hit.slug, path: hit.path, confidence: hit.confidence,
                    source: "match", clause_id: this_clause }
          i += width
        else
          run << tokens[i]
          i += 1
        end
      end
      flush_leftover(run, leftovers)
      trailing = clause_id + tokens.count { |token| MenuText::SEGMENT_BREAK_WORDS.include?(token) }
      [ last_clause, trailing ].max
    end

    def longest_match_at(tokens, start, prefix: [])
      [@max_ngram, tokens.length - start].min.downto(1) do |width|
        phrase = tokens[start, width].join(" ")
        return [ :absence, width ] if absence_at?(tokens, start, width, phrase, prefix: prefix)

        entry = @index[phrase] || @index[singularize_last(phrase)] || @index[strip_plural_s(phrase)]
        return [entry, width] if entry
      end
      nil
    end

    # An absence phrase counts only as a statement about this dish: not
    # when it is negated ("not dairy-free", "isn't dairy-free") and not
    # when it offers an alternative ("dairy-free option available").
    # Either way it falls through and matches as it did before.
    def absence_at?(tokens, start, width, phrase, prefix: [])
      return false unless ABSENCE_PHRASES.include?(phrase)

      context = prefix + tokens
      idx = prefix.length + start
      before = idx.positive? ? context[idx - 1] : nil
      negated = NEGATIONS.include?(before) ||
                (before == "t" && idx >= 2 && CONTRACTION_STEMS.include?(context[idx - 2]))
      return false if negated

      lead = context[[ idx - VARIANT_LEAD_WIDTH, 0 ].max...idx].join(" ")
      return false if VARIANT_LEADS.any? { |v| lead == v || lead.end_with?(" #{v}") }

      Array(tokens[start + width, 3]).none? { |t| ALTERNATIVE_WORDS.include?(t) }
    end

    # Leftover runs still split on connectives ("care and love" is two
    # candidate phrases, not one) — matching already had its chance at
    # the connective-spanning n-grams.
    def flush_leftover(run, leftovers)
      MenuText.split_on_break_words(run).each do |sub|
        trimmed = trim_stopwords(sub)
        leftovers << trimmed.join(" ") if trimmed.any?
      end
      run.clear
    end

    def trim_stopwords(tokens)
      drop = ->(t) { STOPWORDS.include?(t) || t.match?(/\A\d+\z/) }
      tokens.drop_while(&drop).reverse.drop_while(&drop).reverse
    end

    def add_term(term, slug:, path:, kind:)
      confidence = kind == :name ? NAME_CONFIDENCE : ALIAS_CONFIDENCE
      entry = Match.new(slug:, path:, confidence:, kind:)
      [MenuText.normalize(term), singularize_last(MenuText.normalize(term))].uniq.each do |key|
        next if key.empty?
        store_term(key, entry)
      end
    end

    # Collision policy: a catalog name beats any alias for the same
    # phrase; ties within a kind keep the first writer and log, so a
    # taxonomy ambiguity is visible instead of silently order-dependent.
    def store_term(key, entry)
      existing = @index[key]
      if existing.nil?
        @index[key] = entry
      elsif existing.kind == :alias && entry.kind == :name
        @index[key] = entry
      elsif existing.slug != entry.slug && existing.kind == entry.kind
        Rails.logger.warn(
          "IngredientMatcher: term #{key.inspect} maps to both " \
          "#{existing.slug} and #{entry.slug}; keeping #{existing.slug}"
        )
      end
    end

    def singularize_last(phrase)
      words = phrase.split(" ")
      return phrase if words.empty?

      words[-1] = words[-1].singularize
      words.join(" ")
    end

    # Fallback for plurals the inflector mangles: it applies the
    # knives → knife rule to "olives" ("olife") and "cloves" ("clofe").
    # Only consulted after the exact and singularized lookups miss.
    def strip_plural_s(phrase)
      return phrase unless phrase.end_with?("s") && !phrase.end_with?("ss")

      phrase.delete_suffix("s")
    end
  end
end
