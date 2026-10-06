# frozen_string_literal: true

module Menus
  # Applies today's implied-base table (DeterministicResolver) to dishes
  # promoted before it grew. A dish name like "Samosa" implies wheat; a
  # dish published before #766 never got that row, so a Celiac filter
  # still shows it, and a rescan does not reliably replace it (the
  # matcher can leave a renamed dish unmatched and promote a second one).
  #
  # Add-only, and it writes what promotion writes for the same hit: the
  # base as a `derived` row at `suggested`, plus the allergen tag
  # TagDeriver derives from it (wheat -> contains-gluten). That direction
  # is the one the resolver chose because it fails loudly: a wrong wheat
  # row hides a dish with a reason a person can fix, a missing one shows
  # it as safe. A name's own diet claim ("Gluten-Free Pizza") still wins.
  class ImpliedBaseBackfill
    # When each keyword went live (merge time plus a deploy margin). A dish
    # promoted after a keyword went live already went through it, so a
    # base missing there is a person's decision (they removed it), not a
    # gap, and a rerun must not undo it. A dish qualifies only if one of
    # the keywords its name hits is newer than the dish.
    KEYWORDS_SINCE_766 = [ "samosa", "relleno", "gulab jamun" ].freeze
    LIVE_SINCE_638 = Time.utc(2026, 8, 18)      # #638, the original table
    LIVE_SINCE_766 = Time.utc(2026, 10, 6, 2)   # #766, the three above

    # #766 also added wheat ingredients that a scan matches from the dish
    # text (name and description), not from the name table: "Country
    # Gravy", "breaded cod". Old dishes never met them.
    TEXT_SLUGS_SINCE_766 = %w[
      grain-wheat-pancake grain-wheat-bread-biscuit grain-wheat-bread-english-muffin
      grain-wheat-batter grain-wheat-breading grain-wheat-roux grain-wheat-gravy
    ].freeze

    LATER_TERMS = Ingestion::DeterministicResolver::IMPLIED_BASE_TERMS.transform_values do |terms|
      terms.select { |t| KEYWORDS_SINCE_766.any? { |k| t.start_with?(k) } }
    end.freeze
    EARLIER_TERMS = Ingestion::DeterministicResolver::IMPLIED_BASE_TERMS.to_h do |slug, terms|
      [ slug, terms - LATER_TERMS.fetch(slug) ]
    end.freeze

    # `cutoff` is when the earliest rule that produced these rows went
    # live; an edit after it may be a person's correction.
    Change = Data.define(:item_id, :item_name, :restaurant_id, :restaurant_name,
                         :ingredient_slugs, :tag_slugs, :cutoff)
    Failure = Data.define(:item_id, :item_name, :error)
    Result = Data.define(:changes, :reviews, :failures)

    def self.default_scope = Item.published.where(created_at: ...LIVE_SINCE_766)

    # Yields each change as it is made, so a long run that dies partway
    # still shows what it wrote.
    def self.call(apply:, scope: default_scope, &on_change)
      new.call(apply:, scope:, &on_change)
    end

    def initialize
      nodes      = Ingredient.pluck(:slug, :id, :path)
      @ids       = nodes.to_h { |slug, id, _| [ slug, id ] }
      @paths     = nodes.to_h { |_, id, path| [ id, path.to_s ] }
      @tag_ids   = Tag.pluck(:slug, :id).to_h
      @matcher   = Ingestion::IngredientMatcher.new
      @resolver  = Ingestion::DeterministicResolver.new(matcher: @matcher)
    end

    def call(apply:, scope:)
      changes  = []
      reviews  = []
      failures = []

      scope.includes(:restaurant).find_each do |item|
        change = begin
          found = change_for(item)
          # Edited since its keyword went live: maybe a person removed
          # this very base. Nothing records a removal, so list it for a
          # person rather than write over a decision or drop it silently.
          if found && touched_since_live?(item, found)
            reviews << found
            found = nil
          end
          add!(item, found) if found && apply
          found
        rescue StandardError => e
          failures << Failure.new(item_id: item.id, item_name: item.name, error: "#{e.class}: #{e.message}")
          nil
        end
        next if change.nil?

        changes << change
        # Outside the rescue: a reporting failure must stop the run, not
        # mark a dish that was written as failed.
        yield change if block_given?
      end

      Result.new(changes:, reviews:, failures:)
    end

    private

    def change_for(item)
      existing  = item.denormalized_ingredient_ids.filter_map { |id| { path: @paths[id] } if @paths[id] }
      has_wheat = existing.any? { |e| e[:path].start_with?("grain.wheat") }

      # A name keyword live when the dish was promoted gave it wheat then.
      # No wheat now means a person removed it, so nothing the name says
      # may put it back. The description can still name something else
      # (a bunless sandwich that is still "breaded"); those rows go out
      # with the old cutoff, which lands them on the review list, since
      # the dish has been edited since. A person decides; nothing writes.
      name_cutoff = name_cutoff(item.name)
      corrected = name_cutoff && item.created_at >= name_cutoff && !has_wheat

      text = item.created_at < LIVE_SINCE_766 ? text_rows(item, existing, description_only: corrected) : []
      implied = !corrected && name_cutoff && item.created_at < name_cutoff ? @resolver.implied_rows_for_name(item.name, existing + text) : []
      rows = text + implied
      return nil if rows.empty?

      tags = Ingestion::TagDeriver::Allergen.call(resolved_ingredients: rows)
                                           .map { |t| t[:slug] }.uniq
                                           .select { |slug| @tag_ids.key?(slug) }
                                           .reject { |slug| item.denormalized_tag_ids.include?(@tag_ids[slug]) }

      # Every rule that matched counts, even one whose row turned out
      # redundant: a "Biscuit" from September had #638's rule, so an
      # edit since then may be a correction, whatever #766 adds.
      cutoff = [ name_cutoff, (LIVE_SINCE_766 if text.any?) ].compact.min

      Change.new(item_id: item.id, item_name: item.name,
                 restaurant_id: item.restaurant_id, restaurant_name: item.restaurant&.name,
                 ingredient_slugs: rows.map { |r| r[:slug] }, tag_slugs: tags, cutoff:)
    end

    # What a scan today would match for #766's ingredients, with the
    # resolver's rule for claims: a name's own "gluten-free" beats a match
    # in that name, while a description that lists breading is not
    # gluten-free whatever the name says. A generic wheat row does not
    # cover these: avoiding gravy expands down the tree, not up, so a
    # dish needs the gravy row itself. Skipped only when that node or one
    # below it is already there.
    def text_rows(item, existing, description_only: false)
      claims = Ingestion::DietClaims.claims_in(Ingestion::MenuText.segments(item.name))
      in_name = description_only ? [] : @matcher.scan(item.name).first.reject do |m|
        Ingestion::DietClaims.contradicted?(claims, slug: m[:slug], path: m[:path])
      end
      in_description = @matcher.scan(item.description).first

      (in_name + in_description)
        .select { |m| TEXT_SLUGS_SINCE_766.include?(m[:slug]) && @ids.key?(m[:slug]) }
        .uniq { |m| m[:slug] }
        .reject { |m| covered?(m[:path].to_s, existing) }
        .map { |m| { slug: m[:slug], path: m[:path].to_s, confidence: m[:confidence], source: "derived" } }
    end

    def covered?(path, existing)
      existing.any? { |e| e[:path] == path || e[:path].start_with?("#{path}.") }
    end

    # `updated_at` moves on any ingredient change (the array resync
    # stamps it) and on unrelated ones like a photo, so this is
    # conservative: it sends some dishes to review that were never
    # corrected. That costs a person a look; the other way costs a
    # person's correction.
    def touched_since_live?(item, change)
      item.updated_at >= change.cutoff
    end

    # The earliest keyword the name hits decides, nil when it hits none:
    # every keyword here implies the same base, so once any of them was
    # live the dish got that base at promotion. A "Chile Relleno Burrito"
    # from September got wheat from "burrito" even though "relleno" came
    # later.
    def name_cutoff(name)
      segments = Ingestion::MenuText.segments(name)
      return LIVE_SINCE_638 if Ingestion::TagDeriver.keyword_hits(segments, EARLIER_TERMS, confidence: 1.0).any?
      return LIVE_SINCE_766 if Ingestion::TagDeriver.keyword_hits(segments, LATER_TERMS, confidence: 1.0).any?

      nil
    end

    def add!(item, change)
      Item.defer_denormalization do
        change.ingredient_slugs.each do |slug|
          ItemIngredient.create!(item: item, ingredient_id: @ids.fetch(slug),
                                 confidence: "suggested", source: "derived")
        end
        change.tag_slugs.each do |slug|
          ItemTag.create!(item: item, tag_id: @tag_ids.fetch(slug),
                          confidence: "suggested", source: "derived")
        end
        # Weakest link, never an upgrade: confirmed drops to suggested,
        # inferred stays inferred. update_columns, because this changes
        # one enum and must not trip unrelated validations (a legacy
        # photo) on a dish it was never asked to judge.
        item.update_columns(confidence: "suggested", updated_at: Time.current) if item.confidence == "confirmed"
      end
    end
  end
end
