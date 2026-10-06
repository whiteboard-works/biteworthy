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

    LATER_TERMS = Ingestion::DeterministicResolver::IMPLIED_BASE_TERMS.transform_values do |terms|
      terms.select { |t| KEYWORDS_SINCE_766.any? { |k| t.start_with?(k) } }
    end.freeze
    EARLIER_TERMS = Ingestion::DeterministicResolver::IMPLIED_BASE_TERMS.to_h do |slug, terms|
      [ slug, terms - LATER_TERMS.fetch(slug) ]
    end.freeze

    Change = Data.define(:item_id, :item_name, :restaurant_id, :restaurant_name, :ingredient_slugs, :tag_slugs)
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
      @resolver  = Ingestion::DeterministicResolver.new
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
          if found && touched_since_live?(item)
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
      return nil unless item.created_at < live_since(item.name)

      existing = item.denormalized_ingredient_ids.filter_map { |id| { path: @paths[id] } if @paths[id] }
      rows = @resolver.implied_rows_for_name(item.name, existing)
      return nil if rows.empty?

      tags = Ingestion::TagDeriver::Allergen.call(resolved_ingredients: rows)
                                           .map { |t| t[:slug] }
                                           .select { |slug| @tag_ids.key?(slug) }
                                           .reject { |slug| item.denormalized_tag_ids.include?(@tag_ids[slug]) }

      Change.new(item_id: item.id, item_name: item.name,
                 restaurant_id: item.restaurant_id, restaurant_name: item.restaurant&.name,
                 ingredient_slugs: rows.map { |r| r[:slug] }, tag_slugs: tags)
    end

    # `updated_at` moves on any ingredient change (the array resync
    # stamps it) and on unrelated ones like a photo, so this is
    # conservative: it sends some dishes to review that were never
    # corrected. That costs a person a look; the other way costs a
    # person's correction.
    def touched_since_live?(item)
      item.updated_at >= live_since(item.name)
    end

    # The earliest keyword the name hits decides: every keyword here
    # implies the same base, so once any of them was live the dish got
    # that base at promotion, and a missing row means a person removed
    # it. A "Chile Relleno Burrito" from September got wheat from
    # "burrito" even though "relleno" came later.
    def live_since(name)
      segments = Ingestion::MenuText.segments(name)
      earlier  = Ingestion::TagDeriver.keyword_hits(segments, EARLIER_TERMS, confidence: 1.0)
      later    = Ingestion::TagDeriver.keyword_hits(segments, LATER_TERMS, confidence: 1.0)
      later.any? && earlier.none? ? LIVE_SINCE_766 : LIVE_SINCE_638
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
