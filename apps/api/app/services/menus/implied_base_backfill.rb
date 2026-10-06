# frozen_string_literal: true

module Menus
  # Applies today's implied-base table (DeterministicResolver) to dishes
  # promoted before it grew. A dish name like "Samosa" implies wheat; a
  # dish published before #766 never got that row, so a Celiac filter
  # still shows it, and a rescan does not reliably replace it (the
  # matcher can leave a renamed dish unmatched and promote a second one).
  #
  # Add-only, and it writes exactly what promotion writes for the same
  # hit: a `derived` row at `suggested`. That direction is the one the
  # resolver chose because it fails loudly: a wrong wheat row hides a
  # dish with a reason a person can fix, a missing one shows it as safe.
  # The one guard is the same as the resolver's: a name's own diet claim
  # ("Gluten-Free Pizza") wins.
  class ImpliedBaseBackfill
    Change = Data.define(:item_id, :item_name, :restaurant_name, :slugs)

    def self.call(apply:, scope: Item.all)
      new.call(apply:, scope:)
    end

    def initialize(matcher: Ingestion::IngredientMatcher.new)
      @resolver = Ingestion::DeterministicResolver.new(matcher:)
      @paths    = Ingredient.pluck(:id, :path).to_h
      @ids      = Ingredient.pluck(:slug, :id).to_h
    end

    def call(apply:, scope:)
      scope.includes(:restaurant).find_each.filter_map do |item|
        existing = item.denormalized_ingredient_ids.filter_map do |id|
          path = @paths[id]
          { slug: nil, path: path } if path
        end
        rows = @resolver.implied_rows_for_name(item.name, existing)
                        .select { |row| @ids.key?(row[:slug]) }
        next if rows.empty?

        add!(item, rows) if apply
        Change.new(item_id: item.id, item_name: item.name,
                   restaurant_name: item.restaurant&.name, slugs: rows.map { |r| r[:slug] })
      end
    end

    private

    def add!(item, rows)
      Item.transaction do
        Item.defer_denormalization do
          rows.each do |row|
            ItemIngredient.create!(item: item, ingredient_id: @ids.fetch(row[:slug]),
                                   confidence: "suggested", source: "derived")
          end
        end
        # Weakest link, never an upgrade: confirmed drops to suggested,
        # inferred stays inferred.
        item.update!(confidence: "suggested") if item.confidence == "confirmed"
      end
    end
  end
end
