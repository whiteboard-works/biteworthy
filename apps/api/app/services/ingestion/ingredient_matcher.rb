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

    Match = Data.define(:slug, :path, :confidence, :kind)

    def initialize(ingredients = Ingredient.pluck(:slug, :name, :path, :aliases))
      @index = {}
      ingredients.each do |slug, name, path, aliases|
        add_term(name, slug:, path: path.to_s, kind: :name)
        Array(aliases).each { |a| add_term(a, slug:, path: path.to_s, kind: :alias) }
      end
      @max_ngram = @index.keys.map { |k| k.count(" ") + 1 }.max || 1
    end

    # Scan one text; returns [matches, leftovers] where matches is an
    # array of {slug:, path:, confidence:, source:} hashes (deduped by
    # slug, best confidence kept) and leftovers the unmatched text runs
    # that could be ingredients we don't know. The caller decides how
    # name vs description leftovers weigh (see DeterministicResolver).
    def scan(text)
      matches   = {}
      leftovers = []

      MenuText.segments(text).each do |tokens|
        scan_segment(tokens, matches, leftovers)
      end

      [matches.values.map { |m| { slug: m.slug, path: m.path, confidence: m.confidence, source: "match" } },
       leftovers]
    end

    private

    # Greedy longest-match-first n-gram scan. A hit consumes its tokens;
    # unmatched tokens accumulate into leftover runs.
    def scan_segment(tokens, matches, leftovers)
      run = []
      i = 0
      while i < tokens.length
        hit, width = longest_match_at(tokens, i)
        if hit
          flush_leftover(run, leftovers)
          best = matches[hit.slug]
          matches[hit.slug] = hit if best.nil? || hit.confidence > best.confidence
          i += width
        else
          run << tokens[i]
          i += 1
        end
      end
      flush_leftover(run, leftovers)
    end

    def longest_match_at(tokens, start)
      [@max_ngram, tokens.length - start].min.downto(1) do |width|
        phrase = tokens[start, width].join(" ")
        entry = @index[phrase] || @index[singularize_last(phrase)]
        return [entry, width] if entry
      end
      nil
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
  end
end
