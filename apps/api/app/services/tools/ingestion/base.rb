# frozen_string_literal: true

module Tools
  module Ingestion
    # Shared run-scoping for the ingestion tools.
    #
    # Every one of these touches a specific scan, so "signed in" is not
    # enough — the caller must own the run, or be an admin. A run holds
    # someone's unpublished work and, once accepted, writes to a live menu.
    class Base < Tools::Base
      audience :user

      class << self
        def find_run!(context, run_id)
          run = IngestionRun.find(run_id)
          authorize_run!(context, run)
          run
        end

        # Deliberately NotFound rather than Forbidden for a run belonging to
        # someone else: "you may not touch run X" confirms run X exists.
        def authorize_run!(context, run)
          user = context.user!
          return run if user.is_admin?
          return run if run.user_id.present? && run.user_id == user.id

          raise Errors::NotFound, "No scan with id #{run.id}."
        end

        def find_staged_item!(context, item_id)
          item = IngestionItem.find(item_id)
          authorize_run!(context, item.ingestion_run)
          item
        end

        # Staged dishes came out of a photo or a scraped page, so their text
        # is untrusted in exactly the way get_menu's is.
        def staged_item_row(item, include_payloads: true)
          row = {
            id:          item.id,
            position:    item.position,
            name:        untrusted(item.name),
            description: untrusted(item.description),
            section:     item.section_name,
            decision:    item.decision,
            promoted_item_id: item.item_id
          }
          return row.compact unless include_payloads

          row.merge(
            ingredients: Array(item.ingredients_payload).map { |r| payload_row(r) },
            tags:        Array(item.tags_payload).map { |r| payload_row(r) },
            prices:      Array(item.prices_payload),
            addons:      Array(item.addons_payload),
            unresolved:  {
              ingredients: Array(item.unresolved_ingredients),
              tags:        Array(item.unresolved_tags)
            }.compact_blank.presence,
            updates_existing_item: match_row(item)
          ).compact
        end

        # `confidence` and `source` ride along on every association — they
        # are what a verifier needs to decide whether to trust a row, and
        # dropping them to save tokens would hide exactly the wrong thing.
        def payload_row(row)
          ::Ingestion::AssociationPayload.load(row).to_h.compact
        end

        # A matched row means accepting applies an UPDATE to a live dish
        # rather than creating a new one. The model has to say so before the
        # user accepts, or they'll think they're adding and actually be
        # editing.
        def match_row(item)
          target = item.matched_item
          return nil if target.nil?

          diff = ::Ingestion::ItemUpdateDiff.call(item, target)
          {
            item_id:    target.id,
            name:       untrusted(target.name),
            score:      item.match_score,
            no_changes: diff[:no_changes],
            diff:       diff.except(:no_changes).presence
          }.compact
        end
      end
    end
  end
end
