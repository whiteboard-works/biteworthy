module Api
  module V1
    # PATCH /api/v1/ingestion_runs/:run_id/items/:id
    #
    # Phase 2.7 — the mobile swipe-verify UI hits this endpoint when
    # an admin accepts / edits / rejects an item. Accept also fires
    # IngestionItem#promote! (materializes the real Item) and runs
    # IngestionRun#maybe_publish! (the 80%-accepted threshold from
    # Phase 2.5).
    class IngestionItemsController < BaseController
      before_action :ensure_admin!

      def index
        run = IngestionRun.find(params[:ingestion_run_id])
        items = run.ingestion_items.order(:created_at)
        render json: { items: items.map { |it| serialize_item(it) } }
      end

      def update
        run  = IngestionRun.find(params[:ingestion_run_id])
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
        when "accepted", "edited"
          # Edited+then-accepted: a separate request will resubmit
          # decision: accepted. Editing alone records the change but
          # doesn't promote — keeps the human in control of the final
          # promotion step.
          if decision == "accepted"
            item.save! if item.changed?
            item.promote!
          else
            item.update!(decision: "edited", decided_at: Time.current)
          end
        when "rejected"
          item.update!(decision: "rejected", decided_at: Time.current)
        end

        run.maybe_publish!

        render json: serialize_item(item.reload)
      end

      private

      def ensure_admin!
        return if current_user&.is_admin?
        render json: { error: "forbidden" }, status: :forbidden
      end

      def edit_params
        params.permit(
          :name, :description,
          ingredients_payload:    [:slug, :confidence],
          tags_payload:           [:slug, :confidence],
          unresolved_ingredients: [],
          unresolved_tags:        []
        )
      end

      def serialize_item(item)
        {
          id:                     item.id,
          ingestion_run_id:       item.ingestion_run_id,
          item_id:                item.item_id,
          name:                   item.name,
          description:            item.description,
          section_name:           item.section_name,
          decision:               item.decision,
          decided_at:             item.decided_at,
          ingredients_payload:    item.ingredients_payload,
          tags_payload:           item.tags_payload,
          prices_payload:         item.prices_payload,
          unresolved_ingredients: item.unresolved_ingredients,
          unresolved_tags:        item.unresolved_tags
        }
      end
    end
  end
end
