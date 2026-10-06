# frozen_string_literal: true

module Menus
  # Applies today's gluten rules to dishes promoted before those rules
  # existed. Extraction learned in three steps (#638, #766, #794) that a
  # name like "Samosa", text like "breaded", or an ingredient like soy
  # sauce means wheat or barley. A dish promoted before a step never got
  # that row, so a Celiac filter still shows it, and a rescan does not
  # reliably replace it (the matcher can leave a renamed dish unmatched
  # and promote a second one).
  #
  # Add-only, and it writes what promotion writes for the same hit: the
  # row as `derived` at `suggested`, plus the allergen tag TagDeriver
  # derives from it as `ingredient_derived`. That direction is the one
  # the resolver chose because it fails loudly: a wrong wheat row hides
  # a dish with a reason a person can fix, a missing one shows it as
  # safe. A name's own diet claim ("Gluten-Free Pizza") still wins over
  # anything the name says.
  #
  # Each row is judged by the rule set that produces it. A rule that was
  # already live when the dish was promoted already ran on it, so its
  # row missing now is a person's decision, never a gap.
  class ImpliedBaseBackfill
    RuleSet = Data.define(:pr, :live_since, :name_keywords, :text_slugs, :implications) do
      # Same plural bridge as DeterministicResolver::IMPLIED_BASE_TERMS.
      def name_terms
        { "grain-wheat" => name_keywords.flat_map do |kw|
          words = kw.split(" ")
          [ kw, (words[0..-2] + [ words[-1].pluralize ]).join(" ") ]
        end.uniq }
      end
    end

    # live_since is when that PR's deploy-api run finished (gh run list
    # --workflow deploy-api.yml); a dish promoted after it went through the
    # rule. A new keyword,
    # ingredient, or implication in the resolver needs a row here, or old
    # dishes never get it; the spec checks the keyword list stays in step.
    RULE_SETS = [
      RuleSet.new(
        pr: 638, live_since: Time.utc(2026, 8, 17, 23, 16),
        name_keywords: %w[
          pizza pizzetta pizzeta pizzette pizzettas pizzetas calzone stromboli focaccia
          focaccias focacce panini sandwich burger hamburger cheeseburger slider hoagie sub
          wrap burrito quesadilla chimichanga pasta pastas spaghetti fettuccine linguine
          rigatoni macaroni ziti penne lasagna ravioli tortellini gnocchi bread toast crostini
          bruschetta bruschettas bruschette flatbread naan pita pitas cornbread bagel croissant
          biscuit pretzel pancake waffle crepe tempura dumpling gyoza potsticker wonton ramen
          udon cake pie tart brownie cookie donut churro
        ] + [ "lo mein", "chow mein" ],
        text_slugs: [], implications: {}
      ),
      RuleSet.new(
        pr: 766, live_since: Time.utc(2026, 10, 6, 0, 46),
        name_keywords: [ "samosa", "relleno", "gulab jamun" ],
        text_slugs: %w[
          grain-wheat-pancake grain-wheat-bread-biscuit grain-wheat-bread-english-muffin
          grain-wheat-batter grain-wheat-breading grain-wheat-roux grain-wheat-gravy
        ],
        implications: {}
      ),
      RuleSet.new(
        pr: 794, live_since: Time.utc(2026, 10, 6, 2, 42),
        name_keywords: %w[
          battered breaded crusted panko roti chapati paratha puri momo empanada schnitzel
          katsu croquette seitan couscous bulgur farro orzo gravy hotcake
        ] + [ "egg roll", "spring roll", "soy sauce", "malt vinegar" ],
        text_slugs: %w[
          alcohol-porter alcohol-pilsner grain-barley-malt grain-wheat-noodle-ramen
          grain-wheat-bread-roti grain-wheat-bread-chapati grain-wheat-bread-paratha
          grain-wheat-bread-puri grain-wheat-dumpling grain-wheat-dumpling-momo
          grain-wheat-empanada grain-wheat-egg-roll grain-wheat-spring-roll grain-wheat-wonton
          grain-wheat-schnitzel grain-wheat-katsu grain-wheat-croquette grain-wheat-bulgur
          grain-wheat-farro
        ],
        implications: Ingestion::DeterministicResolver::GLUTEN_IMPLICATIONS
      )
    ].freeze

    # The subtrees a Celiac avoid list hides. A row is judged against the
    # one it sits under: a dish can have had its wheat removed and still
    # need barley.
    GLUTEN_ROOTS = %w[grain.wheat grain.barley grain.rye grain.spelt grain.triticale
                      alcohol.beer alcohol.ale].freeze

    # `cutoff` is the earliest go-live among the rules that produced these
    # rows; an edit after it may be a person's correction. `force_review`
    # marks rows under a base a live rule should already have added.
    Change = Data.define(:item_id, :item_name, :restaurant_id, :restaurant_name,
                         :ingredient_slugs, :tag_slugs, :cutoff, :force_review)
    Failure = Data.define(:item_id, :item_name, :error)
    Result = Data.define(:changes, :reviews, :failures)

    def self.default_scope = Item.published.where(created_at: ...RULE_SETS.map(&:live_since).max)

    # Yields each change as it is made, so a long run that dies partway
    # still shows what it wrote.
    def self.call(apply:, scope: default_scope, &on_change)
      new.call(apply:, scope:, &on_change)
    end

    def initialize
      nodes      = Ingredient.pluck(:slug, :id, :path)
      @ids       = nodes.to_h { |slug, id, _| [ slug, id ] }
      @by_id     = nodes.to_h { |slug, id, path| [ id, { slug: slug, path: path.to_s } ] }
      @paths     = nodes.to_h { |slug, _, path| [ slug, path.to_s ] }
      @tag_ids   = Tag.pluck(:slug, :id).to_h
      @matcher   = Ingestion::IngredientMatcher.new
      @terms     = RULE_SETS.to_h { |rs| [ rs.pr, rs.name_terms ] }
    end

    def call(apply:, scope:)
      changes  = []
      reviews  = []
      failures = []

      scope.includes(:restaurant).find_each do |item|
        written = begin
          # One change per gluten base, so a possible wheat correction
          # never holds back a new barley row on the same dish.
          to_write, to_review = changes_for(item).partition do |c|
            # Edited since a rule that produced these rows went live: maybe
            # a person removed one of them. Nothing records a removal, so
            # list it for a person rather than write over a decision or
            # drop it silently.
            !c.force_review && item.updated_at < c.cutoff
          end
          reviews.concat(to_review)
          to_write.each { |c| add!(item, c) } if apply
          to_write
        rescue StandardError => e
          failures << Failure.new(item_id: item.id, item_name: item.name, error: "#{e.class}: #{e.message}")
          []
        end

        changes.concat(written)
        # Outside the rescue: a reporting failure must stop the run, not
        # mark a dish that was written as failed.
        written.each { |c| yield c } if block_given?
      end

      Result.new(changes:, reviews:, failures:)
    end

    private

    # Every row a rule set would add to this dish today, before deciding
    # which ones it may.
    Candidate = Data.define(:slug, :path, :kind, :live_since)

    def changes_for(item)
      existing = item.denormalized_ingredient_ids.filter_map { |id| @by_id[id] }
      claims   = Ingestion::DietClaims.claims_in(Ingestion::MenuText.segments(item.name))
      in_name  = @matcher.scan(item.name).first
      in_desc  = @matcher.scan(item.description).first
      found    = candidates(item, existing, in_name, in_desc)

      # A rule live when the dish was promoted should already have put its
      # base there. The base missing now usually means a person removed it,
      # but not always: a dish added by hand or by an admin tool never went
      # through the resolver. Nothing records which, so every row under
      # that base goes to review: never written over a decision, never
      # dropped without a word.
      corrected = GLUTEN_ROOTS.select do |root|
        found.any? { |c| root_of(c.path) == root && c.live_since <= item.created_at } &&
          existing.none? { |e| under?(e[:path], root) }
      end

      kept = found.select { |c| corrected.include?(root_of(c.path)) || c.live_since > item.created_at }
                  .reject { |c| c.kind != :description && contradicted?(claims, c) }
      dedupe(kept, existing).group_by { |c| root_of(c.path) }.map do |root, rows|
        Change.new(item_id: item.id, item_name: item.name,
                   restaurant_id: item.restaurant_id, restaurant_name: item.restaurant&.name,
                   ingredient_slugs: rows.map(&:slug), tag_slugs: tags_for(item, rows),
                   cutoff: rows.map(&:live_since).min,
                   force_review: corrected.include?(root))
      end
    end

    def candidates(item, existing, in_name, in_desc)
      name_segments = Ingestion::MenuText.segments(item.name)
      present = (existing.map { |e| e[:slug] } + (in_name + in_desc).map { |m| m[:slug] }).to_set

      RULE_SETS.flat_map do |rs|
        hits = Ingestion::TagDeriver.keyword_hits(name_segments, @terms.fetch(rs.pr), confidence: 1.0)
        by_name = hits.map { |h| candidate(h[:slug], :name, rs) }
        text = in_name.select { |m| rs.text_slugs.include?(m[:slug]) }.map { |m| candidate(m[:slug], :name_text, rs) } +
               in_desc.select { |m| rs.text_slugs.include?(m[:slug]) }.map { |m| candidate(m[:slug], :description, rs) }
        implied = rs.implications.filter_map { |source, base| candidate(base, :implication, rs) if present.include?(source) }
        by_name + text + implied
      end.compact
    end

    def candidate(slug, kind, rule_set)
      path = @paths[slug]
      return nil if path.nil? || root_of(path).nil?

      Candidate.new(slug:, path:, kind:, live_since: rule_set.live_since)
    end

    def contradicted?(claims, cand)
      Ingestion::DietClaims.contradicted?(claims, slug: cand.slug, path: cand.path)
    end

    # The resolver's coverage rules: a base (wheat) is covered by anything
    # in its subtree, an exact node (gravy) only by itself or something
    # below it, since avoiding gravy expands down the tree, not up.
    def dedupe(cands, existing)
      specific = cands.reject { |c| c.kind == :name || c.kind == :implication }
      present  = existing.map { |e| e[:path] } + specific.map(&:path)
      bases    = cands.select { |c| c.kind == :name || c.kind == :implication }
                      .reject { |c| present.any? { |p| under?(p, c.path) } }
      (specific.reject { |c| existing.any? { |e| under?(e[:path], c.path) } } + bases)
        .uniq(&:slug)
    end

    def tags_for(item, rows)
      Ingestion::TagDeriver::Allergen.call(resolved_ingredients: rows.map { |r| { slug: r.slug, path: r.path, confidence: 0.8, source: "derived" } })
                                     .map { |t| t[:slug] }.uniq
                                     .select { |slug| @tag_ids.key?(slug) }
                                     .reject { |slug| item.denormalized_tag_ids.include?(@tag_ids[slug]) }
    end

    def root_of(path) = GLUTEN_ROOTS.find { |root| under?(path, root) }

    def under?(path, root) = path == root || path.start_with?("#{root}.")

    def add!(item, change)
      Item.defer_denormalization do
        change.ingredient_slugs.each do |slug|
          ItemIngredient.create!(item: item, ingredient_id: @ids.fetch(slug),
                                 confidence: "suggested", source: "derived")
        end
        # Wheat and barley both derive contains-gluten, and each base is
        # its own change, so the second one finds the tag already there.
        change.tag_slugs.each do |slug|
          ItemTag.find_or_create_by!(item: item, tag_id: @tag_ids.fetch(slug)) do |row|
            row.confidence = "suggested"
            row.source     = "ingredient_derived"
          end
        end
        # Weakest link, never an upgrade: confirmed drops to suggested,
        # inferred stays inferred. update_columns, because this changes
        # one enum and must not trip unrelated validations (a legacy
        # photo) on a dish it was never asked to judge.
        # Not updated_at: the dish's other bases are judged against it, and
        # this write is not a person's edit.
        item.update_columns(confidence: "suggested") if item.confidence == "confirmed"
      end
    end
  end
end
