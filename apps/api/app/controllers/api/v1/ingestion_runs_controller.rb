module Api
  module V1
    # POST /api/v1/ingestion_runs
    #   { restaurant_id: <uuid>, inputs[]: <files> }
    # GET  /api/v1/ingestion_runs/:id
    #
    # Phase 2.6 — the mobile camera capture flow uploads here. Auth-gated
    # to admins (Phase 4 introduces a contributor role). The endpoint
    # creates the run, attaches the images, and kicks off the
    # ExtractMenuJob via the state machine.
    class IngestionRunsController < BaseController
      before_action :ensure_admin!, only: [:create]

      def create
        restaurant = Restaurant.find(params.require(:restaurant_id))
        files      = Array(params[:inputs])

        if files.empty?
          render json: { error: "no_inputs" }, status: :unprocessable_entity
          return
        end

        run = IngestionRun.create!(
          user:       current_user,
          restaurant: restaurant,
          input_kind: detect_input_kind(files.first)
        )
        run.inputs.attach(files)
        run.transition_to!(:extracting)

        render json: serialize_run(run), status: :created
      end

      def show
        run = IngestionRun.find(params[:id])
        # Allow the run's owner OR an admin to read it. Anyone else 404s.
        if run.user_id != current_user.id && !current_user.is_admin?
          render json: { error: "not_found" }, status: :not_found
          return
        end
        render json: serialize_run(run)
      end

      private

      def ensure_admin!
        return if current_user&.is_admin?
        render json: { error: "forbidden" }, status: :forbidden
      end

      def detect_input_kind(file)
        ct = file.respond_to?(:content_type) ? file.content_type.to_s : ""
        return "pdf" if ct.include?("pdf")
        "photo"
      end

      def serialize_run(run)
        {
          id:               run.id,
          status:           run.status,
          input_kind:       run.input_kind,
          restaurant_id:    run.restaurant_id,
          state_history:    run.state_history,
          failure_message:  run.failure_message,
          api_cost_cents:   run.api_cost_cents,
          latency_ms:       run.latency_ms,
          input_count:      run.inputs.attached? ? run.inputs.count : 0,
          ingestion_items_count: run.ingestion_items.count,
          created_at:       run.created_at,
          updated_at:       run.updated_at
        }
      end
    end
  end
end
