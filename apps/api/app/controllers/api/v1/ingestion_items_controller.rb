module Api
  module V1
    # PATCH /api/v1/ingestion_runs/:run_id/items/:id
    #
    # Phase 2.7 — the mobile swipe-verify UI hits this endpoint when
    # an item is accepted / edited / rejected. Accept also fires
    # IngestionItem#promote! (materializes the real Item) and runs
    # IngestionRun#maybe_publish! (the 80%-accepted threshold from
    # Phase 2.5).
    #
    # Phase 6.3 — access widened from admin-only to creator-or-admin:
    # a community scanner verifies their OWN run. promote! receives
    # the deciding user so community verification lands
    # `confidence: suggested` (see the trust model in IngestionItem).
    class IngestionItemsController < BaseController
      before_action :ensure_run_access!

      def index
        run = authorized_run
        items = run.ingestion_items.order(:position, :created_at)
                   .includes(matched_item: %i[item_variants ingredients tags])
        render json: { items: items.map { |it| serialize_item(it) } }
      end

      def update
        run  = authorized_run
        item = run.ingestion_items.find(params[:id])

        decision = params[:decision].to_s
        unless IngestionItem::DECISIONS.include?(decision)
          render json: { error: "invalid_decision",
                         allowed: IngestionItem::DECISIONS }, status: :unprocessable_entity
          return
        end

        # Edits override fields BEFORE accept fires promote!, so the
        # materialized Item carries the human's tweaks rather than
        # the AI's original suggestions.
        if decision == "edited" || decision == "accepted"
          item.assign_attributes(edit_params) if edit_params.to_h.any?
        end

        case decision
        when "accepted"
          item.save! if item.changed?
          apply_acceptance!(run, item)
        when "edited"
          # Editing alone records the change but doesn't promote — keeps the
          # human in control of the final acceptance step.
          item.update!(decision: "edited", decided_at: Time.current)
        when "rejected"
          item.update!(decision: "rejected", decided_at: Time.current)
        when "pending"
          undo_decision!(item)
        end

        run.maybe_publish!

        render json: serialize_item(item.reload)
      end

      # POST /api/v1/ingestion_runs/:run_id/items/accept_all
      #
      # Bulk-accept every still-pending item, applying the same rule as a
      # single accept: promote now if the run is enriched (:staged/:published),
      # else record the acceptance for ResolveItemsJob to promote at :staged.
      def accept_all
        run = authorized_run

        ActiveRecord::Base.transaction do
          run.ingestion_items.where(decision: "pending").find_each do |item|
            apply_acceptance!(run, item)
          end
        end

        run.maybe_publish!

        items = run.ingestion_items.order(:position, :created_at)
                   .includes(matched_item: %i[item_variants ingredients tags])
        render json: { items: items.map { |it| serialize_item(it) } }
      end

      private

      # Accept an item: promote it to a real Item now if the run is enriched,
      # otherwise record the acceptance and defer promote! to the :staged
      # batch-promote — an Item must never go live without its payloads.
      def apply_acceptance!(run, item)
        if run.staged? || run.published?
          item.promote!(decided_by: current_user)
        else
          item.update!(decision: "accepted", decided_at: Time.current)
        end
      end

      # Undo — revert a decision to pending. If the item was promoted (its Item
      # is live on the restaurant), remove that Item + its ingredient/tag joins.
      # The FK ingestion_items.item_id → items is RESTRICT, so release it first.
      def undo_decision!(item)
        promoted = item.item
        item.update!(decision: "pending", item_id: nil, decided_at: nil)
        promoted&.destroy
      end

      # The run's creator or an admin. Memoized so index/update don't
      # re-fetch what the before_action already loaded.
      def authorized_run
        @authorized_run ||= IngestionRun.find(params[:ingestion_run_id])
      end

      def ensure_run_access!
        return if current_user&.is_admin?
        return if authorized_run.user_id.present? && authorized_run.user_id == current_user&.id

        render json: { error: "forbidden" }, status: :forbidden
      end

      def edit_params
        params.permit(
          :name, :description,
          ingredients_payload:    [:slug, :confidence, :source],
          tags_payload:           [:slug, :confidence, :source],
          addons_payload:         [:name, :price_cents, :source],
          unresolved_ingredients: [],
          unresolved_tags:        []
        )
      end

      def serialize_item(item)
        {
          id:                     item.id,
          ingestion_run_id:       item.ingestion_run_id,
          item_id:                item.item_id,
          position:               item.position,
          name:                   item.name,
          description:            item.description,
          section_name:           item.section_name,
          decision:               item.decision,
          decided_at:             item.decided_at,
          ingredients_payload:    item.ingredients_payload,
          tags_payload:           item.tags_payload,
          prices_payload:         item.prices_payload,
          addons_payload:         item.addons_payload,
          unresolved_ingredients: item.unresolved_ingredients,
          unresolved_tags:        item.unresolved_tags,
          match:                  serialize_match(item)
        }
      end

      # Re-scan dedup — the existing Item this staged row matched, with a
      # serialize-time diff (never stored: gap-fill keeps appending to the
      # payloads after :staged, so a stored diff would lie). nil for
      # unmatched rows, i.e. plain "new item" cards.
      def serialize_match(item)
        target = item.matched_item
        return nil if target.nil?

        diff = Ingestion::ItemUpdateDiff.call(item, target)
        {
          item_id: target.id,
          score:   item.match_score,
          existing: {
            name:        target.name,
            description: target.description,
            prices: target.item_variants.sort_by(&:position).map do |v|
              { size: v.size, price_cents: v.price_cents }
            end
          },
          diff:       diff.except(:no_changes),
          no_changes: diff[:no_changes]
        }
      end
    end
  end
end
