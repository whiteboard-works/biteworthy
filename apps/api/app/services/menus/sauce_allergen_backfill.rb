# frozen_string_literal: true

module Menus
  # Applies Ingestion::IngredientImplications (#907) to dishes it never
  # ran on: a dish carrying `condiment-aioli` with no egg row still shows
  # as safe to an egg-avoider until this adds the egg.
  #
  # Add-only, and it writes what ImpliedBaseBackfill writes for a gluten
  # base: the implied row as `derived` at `suggested`, the allergen tag
  # TagDeriver derives from it, and the dish's confidence lowered to
  # `suggested` if it was `confirmed`. A name's diet claim ("Vegan
  # Caesar") still vetoes, through the same check the resolver uses.
  #
  # Every published dish carrying a listed sauce is judged, whenever it was
  # created: a scan resolved before #907 and accepted after it never went
  # through the rule either. A dish edited since the rule went live may
  # have had the row removed on purpose, and nothing records that, so it
  # goes to a review list instead of being written over.
  class SauceAllergenBackfill
    LIVE_SINCE = Time.utc(2026, 10, 12, 21, 8) # deploy-api run for #907 finished 21:07:54

    Change  = Data.define(:item_id, :item_name, :restaurant_id, :restaurant_name, :ingredient_slugs, :tag_slugs)
    Failure = Data.define(:item_id, :item_name, :error)
    Result  = Data.define(:changes, :reviews, :failures)

    def self.call(apply:, scope: Item.published, &on_change)
      new.call(apply:, scope:, &on_change)
    end

    def initialize
      nodes    = Ingredient.pluck(:slug, :id, :path)
      @ids     = nodes.to_h { |slug, id, _| [ slug, id ] }
      @by_id   = nodes.to_h { |slug, id, path| [ id, { slug: slug, path: path.to_s } ] }
      @paths   = nodes.to_h { |slug, _, path| [ slug, path.to_s ] }
      @tag_ids = Tag.pluck(:slug, :id).to_h
      @sauce_ids = Ingestion::IngredientImplications::TABLE.keys.filter_map { |slug| @ids[slug] }
    end

    def call(apply:, scope:)
      changes  = []
      reviews  = []
      failures = []

      # The same array overlap Cities::RestaurantRanking uses: only dishes
      # carrying a listed sauce can change.
      candidates = scope.where("items.ingredient_ids && ARRAY[?]::uuid[]", @sauce_ids)
      candidates.includes(:restaurant).find_each do |item|
        change = change_for(item)
        next unless change

        if item.updated_at > LIVE_SINCE
          reviews << change
          next
        end

        begin
          add!(item, change) if apply
        rescue StandardError => e
          failures << Failure.new(item_id: item.id, item_name: item.name, error: "#{e.class}: #{e.message}")
          next
        end
        changes << change
        yield change if block_given?
      end

      Result.new(changes:, reviews:, failures:)
    end

    private

    def change_for(item)
      existing = item.denormalized_ingredient_ids.filter_map { |id| @by_id[id] }
      claims   = Ingestion::DietClaims.claims_in(Ingestion::MenuText.segments(item.name))
      implied  = Ingestion::IngredientImplications
                   .implied(existing.map { |e| e[:slug] }, path_for: @paths.method(:[]), claims: claims)
                   .reject { |_slug, path| existing.any? { |e| under?(e[:path], path) } }
      return if implied.empty?

      Change.new(item_id: item.id, item_name: item.name,
                 restaurant_id: item.restaurant_id, restaurant_name: item.restaurant&.name,
                 ingredient_slugs: implied.map(&:first), tag_slugs: tags_for(item, implied))
    end

    def tags_for(item, implied)
      rows = implied.map { |slug, path| { slug: slug, path: path, confidence: 0.8, source: "derived" } }
      Ingestion::TagDeriver::Allergen.call(resolved_ingredients: rows)
                                     .map { |t| t[:slug] }.uniq
                                     .select { |slug| @tag_ids.key?(slug) }
                                     .reject { |slug| item.denormalized_tag_ids.include?(@tag_ids[slug]) }
    end

    def under?(path, root) = path == root || path.start_with?("#{root}.")

    # Same writes as ImpliedBaseBackfill#add!, through the join rows so
    # their callbacks rebuild the denormalized arrays. defer_denormalization
    # runs in its own transaction and its resync stamps updated_at, so a
    # dish this wrote is judged as edited on a later run — harmless, since
    # it then carries the rows and produces no change.
    def add!(item, change)
      Item.defer_denormalization do
        change.ingredient_slugs.each do |slug|
          ItemIngredient.create!(item: item, ingredient_id: @ids.fetch(slug),
                                 confidence: "suggested", source: "derived")
        end
        change.tag_slugs.each do |slug|
          ItemTag.find_or_create_by!(item: item, tag_id: @tag_ids.fetch(slug)) do |row|
            row.confidence = "suggested"
            row.source     = "ingredient_derived"
          end
        end
        item.update_columns(confidence: "suggested") if item.confidence == "confirmed"
      end
    end
  end
end
