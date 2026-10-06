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
    # Dishes promoted after this went through the current table, so a
    # missing base there is a person's decision (they removed it), not a
    # gap. Scoping to older dishes keeps a rerun from undoing that fix.
    PROMOTED_BEFORE = Time.utc(2026, 10, 7)

    Change = Data.define(:item_id, :item_name, :restaurant_name, :ingredient_slugs, :tag_slugs)
    Failure = Data.define(:item_id, :item_name, :error)
    Result = Data.define(:changes, :failures)

    def self.default_scope = Item.published.where(created_at: ...PROMOTED_BEFORE)

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
      failures = []

      scope.includes(:restaurant).find_each do |item|
        change = change_for(item)
        next if change.nil?

        add!(item, change) if apply
        changes << change
        yield change if block_given?
      rescue StandardError => e
        failures << Failure.new(item_id: item.id, item_name: item.name, error: "#{e.class}: #{e.message}")
      end

      Result.new(changes:, failures:)
    end

    private

    def change_for(item)
      existing = item.denormalized_ingredient_ids.filter_map { |id| { path: @paths[id] } if @paths[id] }
      rows = @resolver.implied_rows_for_name(item.name, existing)
      return nil if rows.empty?

      tags = Ingestion::TagDeriver::Allergen.call(resolved_ingredients: rows)
                                           .map { |t| t[:slug] }
                                           .select { |slug| @tag_ids.key?(slug) }
                                           .reject { |slug| item.denormalized_tag_ids.include?(@tag_ids[slug]) }

      Change.new(item_id: item.id, item_name: item.name, restaurant_name: item.restaurant&.name,
                 ingredient_slugs: rows.map { |r| r[:slug] }, tag_slugs: tags)
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
