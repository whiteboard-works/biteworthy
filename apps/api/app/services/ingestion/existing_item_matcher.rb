module Ingestion
  # Matches staged IngestionItems against the restaurant's existing Items
  # so a re-scan stages updates instead of duplicating the menu.
  # Deterministic, no LLM: normalized-token equality first, then a pg_trgm
  # similarity band guarded by a token-subset veto. Greedy one-to-one —
  # each existing Item is claimed by at most one staged item per pass.
  #
  # Returns { ingestion_item_id => { item_id:, score: } }.
  #
  # Calibration (similarity() on lowercased names, probed 2026-07-30):
  #
  #   same dish:      carne asada taco | carne asada tacos    0.842  (exact after singularize)
  #                   mac & cheese     | mac and cheese       0.733  (exact after stopword strip)
  #                   margherita pizza | margarita pizza      0.650  <- must clear the threshold
  #   different dish: chicken burrito  | chicken burrito bowl 0.800  <- subset veto
  #                   caesar salad     | side caesar salad    0.765  <- subset veto
  #                   cheeseburger     | bacon cheeseburger   0.684  <- subset veto
  #                   chicken quesadilla | cheese quesadilla  0.542  <- must stay below
  #
  # No raw-similarity threshold separates the containment pairs (0.684+)
  # from real plural/spelling variants — hence the veto: a name whose
  # token set strictly contains the other's is a different dish ("Chicken
  # Burrito Bowl" is not an update to "Chicken Burrito"). That leaves the
  # 0.542–0.650 gap, split at SIMILARITY_THRESHOLD = 0.60. A false merge
  # silently corrupts a live menu item while a missed match is just a
  # duplicate card a human can reject — when in doubt, don't match.
  class ExistingItemMatcher
    SIMILARITY_THRESHOLD = 0.60
    STOPWORDS = %w[and with w the of].freeze

    def self.call(run:, items:)
      new(run: run, items: items).call
    end

    def initialize(run:, items:)
      @run = run
      @items = items
    end

    def call
      return {} if run.restaurant_id.blank?

      staged = items.select { |i| i.item_id.nil? && i.name.present? }
      return {} if staged.empty?

      candidates = eligible_candidates
      return {} if candidates.empty?

      exact = exact_pairs(staged, candidates)
      matched_staged_ids = exact.map { |p| p[:staged].id }.to_set
      fuzzy = fuzzy_pairs(staged.reject { |i| matched_staged_ids.include?(i.id) }, candidates)

      assign(exact + fuzzy)
    end

    private

    attr_reader :run, :items

    # Existing menu minus removed items and minus Items this run already
    # promoted (their staged rows are done; a second staged copy of the
    # same dish must not "update" what this run just created).
    def eligible_candidates
      linked = run.ingestion_items.where.not(item_id: nil).pluck(:item_id)
      scope = run.restaurant.items.where.not(status: "removed")
      scope = scope.where.not(id: linked) if linked.any?
      scope.select(:id, :name).to_a
    end

    def exact_pairs(staged, candidates)
      by_key = candidates.group_by { |c| token_key(c.name) }
      staged.flat_map do |ingestion_item|
        (by_key[token_key(ingestion_item.name)] || []).map do |candidate|
          { staged: ingestion_item, item_id: candidate.id, score: 1.0 }
        end
      end
    end

    # pg_trgm already ignores case and punctuation, so similarity runs on
    # the raw names; the veto runs on normalized token sets.
    def fuzzy_pairs(staged, candidates)
      candidate_ids = candidates.map(&:id)
      tokens_by_id = candidates.to_h { |c| [c.id, tokens(c.name).to_set] }

      staged.flat_map do |ingestion_item|
        staged_tokens = tokens(ingestion_item.name).to_set
        scored_candidates(candidate_ids, ingestion_item.name).filter_map do |row|
          candidate_tokens = tokens_by_id.fetch(row.id)
          next if subset?(staged_tokens, candidate_tokens)

          { staged: ingestion_item, item_id: row.id, score: row.match_score.to_f }
        end
      end
    end

    def scored_candidates(candidate_ids, name)
      Item.where(id: candidate_ids)
          .where("similarity(items.name, ?) >= ?", name, SIMILARITY_THRESHOLD)
          .select(
            "items.id",
            Arel.sql(ActiveRecord::Base.sanitize_sql_array(
                       ["similarity(items.name, ?) AS match_score", name]
                     ))
          )
    end

    def subset?(a, b)
      return false if a == b

      a.subset?(b) || b.subset?(a)
    end

    # Best score wins; ties break on staged position then candidate id so
    # re-runs assign identically.
    def assign(pairs)
      claimed_staged = Set.new
      claimed_items = Set.new
      matches = {}

      sorted = pairs.sort_by { |p| [-p[:score], p[:staged].position || 0, p[:item_id]] }
      sorted.each do |pair|
        staged_id = pair[:staged].id
        next if claimed_staged.include?(staged_id) || claimed_items.include?(pair[:item_id])

        claimed_staged << staged_id
        claimed_items << pair[:item_id]
        matches[staged_id] = { item_id: pair[:item_id], score: pair[:score] }
      end

      matches
    end

    # Transliterate first so "Jalapeño" and "Jalapeno" tokenize
    # identically instead of the ñ shattering into a stray token.
    def tokens(name)
      I18n.transliterate(name.to_s).downcase.gsub(/[^a-z0-9\s]/, " ").split
          .map(&:singularize) - STOPWORDS
    end

    def token_key(name)
      tokens(name).sort.join(" ")
    end
  end
end
