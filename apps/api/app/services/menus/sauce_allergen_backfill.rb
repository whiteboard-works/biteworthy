# frozen_string_literal: true

module Menus
  # Applies Ingestion::IngredientImplications (#907) to dishes promoted
  # before it: a dish carrying `condiment-aioli` with no egg row still
  # shows as safe to an egg-avoider until this adds the egg.
  #
  # Add-only and idempotent, and it writes exactly what ImpliedBaseBackfill
  # writes for a gluten base: the implied row as `derived` at `suggested`,
  # the allergen tag TagDeriver derives from it, and the dish's confidence
  # lowered to `suggested` if it was `confirmed`. A name's diet claim
  # ("Vegan Caesar") still vetoes, through the same check the resolver uses.
  #
  # Dishes promoted after #907 went live already passed through the rule,
  # so a missing row there may be a person's removal; they are out of scope.
  class SauceAllergenBackfill
    LIVE_SINCE = Time.utc(2026, 10, 12, 21, 8) # deploy-api run for #907 finished 21:07:54

    Change  = Data.define(:item_id, :item_name, :restaurant_id, :restaurant_name, :ingredient_slugs, :tag_slugs)
    Failure = Data.define(:item_id, :item_name, :error)
    Result  = Data.define(:changes, :failures)

    def self.default_scope = Item.published.where(created_at: ...LIVE_SINCE)

    def self.call(apply:, scope: default_scope, &on_change)
      new.call(apply:, scope:, &on_change)
    end

    def initialize
      nodes    = Ingredient.pluck(:slug, :id, :path)
      @ids     = nodes.to_h { |slug, id, _| [ slug, id ] }
      @by_id   = nodes.to_h { |slug, id, path| [ id, { slug: slug, path: path.to_s } ] }
      @paths   = nodes.to_h { |slug, _, path| [ slug, path.to_s ] }
      @tag_ids = Tag.pluck(:slug, :id).to_h
    end

    def call(apply:, scope:)
      changes  = []
      failures = []

      scope.includes(:restaurant).find_each do |item|
        change = change_for(item)
        next unless change

        begin
          Item.transaction { add!(item, change) } if apply
        rescue StandardError => e
          failures << Failure.new(item_id: item.id, item_name: item.name, error: "#{e.class}: #{e.message}")
          next
        end
        changes << change
        yield change if block_given?
      end

      Result.new(changes:, failures:)
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

    # Same writes as ImpliedBaseBackfill#add!: through the join rows (their
    # callbacks rebuild the denormalized arrays), and a weakest-link
    # confidence drop that leaves updated_at alone.
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
