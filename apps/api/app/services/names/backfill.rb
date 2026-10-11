# frozen_string_literal: true

module Names
  # Rewrites dishes saved before `Names::Standard` existed. New writes
  # are normalized on assignment; these rows only change when something
  # rewrites them. Behind `bin/rails names:normalize` and the admin tool
  # `normalize_item_names`.
  class Backfill
    Change = Data.define(:item, :before, :after)

    def initialize(scope = Item.all)
      @scope = scope
    end

    def call(dry_run:)
      @scope.find_each.filter_map do |item|
        before = { name: item.name, description: item.description }
        after  = { name: Standard.item_name(item.name), description: Standard.description(item.description) }
        next if after == before

        # Only the fields that change, so a concurrent edit to the other
        # one is not overwritten from this stale read.
        item.update_columns(**after.reject { |field, value| before[field] == value }, updated_at: Time.current) unless dry_run
        Change.new(item: item, before: before, after: after)
      end
    end
  end
end
