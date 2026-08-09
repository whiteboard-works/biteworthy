# A join table that feeds a denormalized uuid[] on `items`:
# item_ingredients → items.ingredient_ids, item_tags → items.tag_ids. The
# array is what the GIN-indexed filter queries hit; the join rows stay the
# source of truth + audit log, so the array is always RECOMPUTED from them
# and never patched in place.
#
# Syncing per row rewrites the whole array once per join, which is most of
# the cost of attaching a dish's ingredients. Bulk writers wrap their loop
# in `Item.defer_denormalization` and each touched item is rebuilt once.
module SyncsDenormalizedIds
  extend ActiveSupport::Concern

  PENDING_KEY = :syncs_denormalized_ids_pending

  included do
    after_save    :sync_denormalized_ids
    after_destroy :sync_denormalized_ids
  end

  class << self
    # Buffered item ids are only ever a hint — the flush recomputes from the
    # join table, so a redundant (or since-rolled-back) id can only re-derive
    # the value already there.
    #
    # The transaction is what makes deferral safe, and it is opened here
    # rather than asked of the caller: on the way out the arrays are rebuilt
    # before the commit, and on a raise the flush is skipped because the join
    # writes it would have covered roll back with it. A dish on a live menu
    # with an array that disagrees with its join rows is the one outcome this
    # must not have — issuing the flush on a doomed transaction would only
    # bury the real error under InFailedSqlTransaction.
    #
    # `requires_new: true` is what makes that true when a caller already has
    # a transaction open. Without it Rails joins the caller's, so a raise
    # inside the block skips the flush (by design) while the join writes stay
    # put (not by design) if the caller rescues and carries on — which is
    # exactly what `AcceptStagedItems` does per dish. The result would be the
    # one outcome the paragraph above says is impossible, arrived at quietly.
    # `promote!` takes a savepoint for the same reason.
    def defer(&block)
      return block.call if pending

      Item.transaction(requires_new: true) do
        ActiveSupport::IsolatedExecutionState[PENDING_KEY] = Hash.new { |h, k| h[k] = Set.new }
        begin
          result = block.call
          pending.each { |model, item_ids| model.resync_denormalized_ids(item_ids) }
          result
        ensure
          ActiveSupport::IsolatedExecutionState.delete(PENDING_KEY)
        end
      end
    end

    def pending
      ActiveSupport::IsolatedExecutionState[PENDING_KEY]
    end
  end

  class_methods do
    # `column` is the array on items this join feeds; `foreign_key` is this
    # join's fk to the taxonomy node the array holds.
    def denormalizes(column:, foreign_key:)
      @denormalized_column      = column
      @denormalized_foreign_key = foreign_key
    end

    attr_reader :denormalized_column, :denormalized_foreign_key

    # One UPDATE for the whole batch. The array is rebuilt by the statement
    # that writes it rather than read into Ruby first, so a join row inserted
    # concurrently can't be lost in the gap between a SELECT and an UPDATE —
    # for allergen data that gap is a wrong answer, not a stale one.
    #
    # The trade, and the one thing to know before reaching for this: a batch
    # UPDATE cannot write through to in-memory records the way the per-row
    # `update_columns` it replaced did. An `Item` you already hold keeps the
    # array it was loaded with until you `reload` it. Every reader in the app
    # goes through `Menus::Query`, which loads items from the database, so
    # nothing live depends on the old behaviour — but code that writes joins
    # and then reads `denormalized_*` off the same object will read staleness
    # rather than an error, which is the kind of bug that surfaces as a dish
    # filtered wrongly rather than as a failure.
    #
    # Bulk writers that use insert_all (no callbacks) call this directly.
    def resync_denormalized_ids(item_ids)
      ids = Array(item_ids).compact.uniq
      return if ids.empty?

      column = connection.quote_column_name(denormalized_column)
      fk     = connection.quote_column_name(denormalized_foreign_key)
      joins  = connection.quote_table_name(table_name)

      Item.where(id: ids).update_all([
        "#{column} = (SELECT COALESCE(array_agg(j.#{fk}), '{}'::uuid[]) " \
        "FROM #{joins} j WHERE j.item_id = items.id), updated_at = ?",
        Time.current
      ])
    end
  end

  private

  def sync_denormalized_ids
    buffer = SyncsDenormalizedIds.pending
    return buffer[self.class] << item_id if buffer

    self.class.resync_denormalized_ids([item_id])
  end
end
