# frozen_string_literal: true

module Tools
  module Ingestion
    # The tool that puts food on a live menu. Everything upstream is staging;
    # this is the commit.
    class AcceptStagedItems < Tools::Ingestion::Base
      tool_name "accept_staged_items"
      title "Publish scanned dishes to the menu"
      description <<~TEXT
        Accept staged dishes and put them on the restaurant's live menu.

        THIS IS THE STEP THAT PUBLISHES. Confirm with the user before calling
        it. Show them what they are accepting first — especially any dish
        whose `updates_existing_item` is set, because accepting that EDITS a
        dish already on the menu instead of adding a new one.

        Pass `item_ids` for specific dishes, or `all: true` to accept every
        pending and edited dish in the scan. Prefer `item_ids` unless the user
        explicitly asked for all of them; `all: true` on a scan they have not
        reviewed publishes unverified data.

        Trust: when an admin accepts, associations are recorded as confirmed
        and are visible to strict-mode users. When a regular contributor
        accepts their own scan, associations are recorded as suggested —
        live for most people, hidden from strict-mode users until an admin
        confirms them. Say which applies if the user asks why a dish is not
        showing up for them.

        A dish that another scan of this restaurant has put on the menu since
        this one was staged is not accepted: it comes back under
        `needs_review` with the live dish it would update, and its staged
        card now shows `updates_existing_item`. Show the user, then accept it
        again to apply it as an update rather than a duplicate.

        Reversible with `undo_staged_item`.
      TEXT

      input_schema(
        properties: {
          scan_id:  { type: "string", description: "The scan id." },
          item_ids: {
            type: "array", items: { type: "string" },
            description: "Staged dish ids to accept."
          },
          all: {
            type: "boolean",
            description: "Accept every still-pending dish in the scan. Only when the user asked for that."
          }
        },
        required: ["scan_id"]
      )

      # destructive_hint: writes to a live menu, and a client that surfaces
      # this hint should be asking the user first.
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      # `undo_staged_item` exists precisely to reverse this, and reverses
      # what it did to the live menu with it.
      unrecoverable_when { false }

      running_description { "Publishing the dishes to the menu" }

      def self.perform(context:, scan_id:, item_ids: nil, all: false)
        user = context.user!
        run  = find_run!(context, scan_id)

        items = select_items(run, item_ids, all)
        raise Errors::InvalidArgument, "Nothing to accept — pass item_ids, or all: true." if items.empty?

        late = run.staged? || run.published? ? rematch_unmatched!(run, items) : {}

        accepted = []
        failed   = []
        review   = []

        items.each do |item|
          # Held back: the reviewer saw this as a new dish, and accepting it
          # now would edit a live one. Its card now shows the match; a
          # second accept is the confirmation.
          if late.key?(item.id)
            review << { id: item.id, name: untrusted(item.name), updates_existing_item: late[item.id] }
            next
          end

          accepted << accept_one(run, item, user)
        rescue StandardError => e
          # One bad dish must not abandon the rest half-published. Report it
          # and keep going, then tell the model exactly what didn't land.
          Rails.logger.error("accept_staged_items: IngestionItem##{item.id} failed: #{e.class} #{e.message}")
          failed << { id: item.id, name: item.name, error: e.message }
        end

        run.maybe_publish!
        run.reload

        ok(
          accepted:  accepted,
          failed:    failed.presence,
          needs_review: review.presence,
          restaurant_published: Restaurant.published.exists?(id: run.restaurant_id),
          remaining_pending: run.ingestion_items.where(decision: %w[pending edited]).count
        )
      end

      def self.select_items(run, item_ids, all)
        return run.ingestion_items.where(decision: %w[pending edited]).order(:position).to_a if all

        ids = Array(item_ids).map(&:to_s).reject(&:blank?)
        return [] if ids.empty?

        found = run.ingestion_items.where(id: ids).order(:position).to_a
        missing = ids - found.map(&:id)
        raise Errors::NotFound, "No staged dish(es) with id(s): #{missing.join(', ')}." if missing.any?

        found
      end
      private_class_method :select_items

      # A dish another scan of this restaurant put on the menu after this
      # one resolved was never a match candidate (four PDFs of one menu
      # scanned at once all resolve against an empty menu), so accepting
      # both would double every shared dish. One matcher pass per accept,
      # the same matcher resolve uses, records those matches so the dish
      # becomes an update rather than a twin.
      #
      # Nobody saw the match before deciding, so it is narrower than
      # resolve's — exact names, pending rows, published dishes, and never a
      # live dish another row of this scan already claims — and the dish is
      # held back from this accept for the reviewer to confirm. Returns
      # { ingestion_item_id => live item id } for the ones held back.
      def self.rematch_unmatched!(run, items)
        unmatched = items.select { |i| i.decision == "pending" && i.matched_item_id.nil? && i.item_id.nil? }
        return {} if unmatched.empty?

        matches = ::Ingestion::ExistingItemMatcher.call(run: run, items: unmatched)
                                                  .select { |_id, m| m[:score] >= 1.0 }
        return {} if matches.empty?

        published = Item.where(id: matches.values.map { |m| m[:item_id] }, status: "published").pluck(:id).to_set
        claimed = run.ingestion_items.where.not(matched_item_id: nil).pluck(:matched_item_id).to_set
        matches.each_with_object({}) do |(id, match), held|
          next if !published.include?(match[:item_id]) || claimed.include?(match[:item_id])

          changed = IngestionItem.where(id: id, matched_item_id: nil)
                                 .update_all(matched_item_id: match[:item_id], match_score: match[:score])
          if changed == 1
            claimed << match[:item_id]
            held[id] = match[:item_id]
          elsif (current = IngestionItem.where(id: id).pick(:matched_item_id))
            # A concurrent accept recorded a match first; this one must not
            # promote past the confirmation either.
            held[id] = current
          end
        end
      end
      private_class_method :rematch_unmatched!

      # Promote now when the run is enriched; otherwise record the acceptance
      # and let the resolve pass promote at :staged. An Item must never go
      # live without its ingredient payload — that would be a dish on a
      # filtered menu with nothing to filter on.
      def self.accept_one(run, item, user)
        if run.staged? || run.published?
          promoted = item.promote!(decided_by: user)
          { id: item.id, name: untrusted(item.name), item_id: promoted&.id,
            updated_existing: item.matched_item_id.present? && promoted&.id == item.matched_item_id }
        else
          item.update!(decision: "accepted", decided_at: Time.current)
          { id: item.id, name: untrusted(item.name), item_id: nil, deferred: true }
        end
      end
      private_class_method :accept_one
    end
  end
end
