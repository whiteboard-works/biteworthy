# frozen_string_literal: true

module Names
  # Rewrites dishes saved before `Names::Standard` existed. New writes
  # are normalized on assignment; these rows only change when something
  # rewrites them. Behind `bin/rails names:normalize` and the admin tool
  # `normalize_item_names`.
  class Backfill
    Change = Data.define(:item, :before, :after)
    Result = Data.define(:changes, :stale, :locked)

    # `editable` is the caller's edit check, so a dish the restaurant
    # verified keeps the text it approved (see `Item#can_be_edited_by?`).
    def initialize(scope = Item.all, editable: ->(_item) { true })
      @scope    = scope
      @editable = editable
    end

    # A row edited between the read and the write is left alone and
    # counted in `stale`; running again picks it up.
    def call(dry_run:)
      stale   = 0
      locked  = 0
      changes = @scope.find_each.filter_map do |item|
        before = { name: item.name, description: item.description }
        after  = { name: Standard.item_name(item.name), description: Standard.description(item.description) }
        next if after == before

        unless @editable.call(item)
          locked += 1
          next
        end

        unless dry_run || write_if_unchanged(item, before, after)
          stale += 1
          next
        end
        Change.new(item: item, before: before, after: after)
      end
      Result.new(changes: changes, stale: stale, locked: locked)
    end

    private

    # A string condition, because `normalizes` rewrites hash conditions
    # and would compare against the normalized text instead of what was read.
    # The verification stamp is in it too, so a dish verified after the
    # `editable` check is left as approved.
    def write_if_unchanged(item, before, after)
      Item.where(id: item.id)
          .where("name = ? AND description IS NOT DISTINCT FROM ?", before[:name], before[:description])
          .where("restaurant_verified_at IS NOT DISTINCT FROM ?", item.restaurant_verified_at)
          .update_all(after.reject { |field, value| before[field] == value }.merge(updated_at: Time.current))
          .positive?
    end
  end
end
