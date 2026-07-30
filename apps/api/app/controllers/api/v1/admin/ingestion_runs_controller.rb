module Api
  module V1
    module Admin
      # GET  /api/v1/admin/ingestion_runs — the cross-user moderation
      # queue (web-admin twin of Avo's CommunityRuns filter).
      # POST /api/v1/admin/ingestion_runs/:id/re_extract
      #
      # Per-run item review deliberately reuses the existing
      # creator-or-admin ingestion endpoints; only the cross-user queue
      # and the rewind are admin-only.
      class IngestionRunsController < BaseController
        DEFAULT_LIMIT = 25
        MAX_LIMIT     = 100

        def index
          runs = IngestionRun.order(created_at: :desc).includes(:user, :restaurant)
          if IngestionRun::STATUSES.include?(params[:status].to_s)
            runs = runs.where(status: params[:status].to_s)
          end
          # Runs scanned by non-admins — what actually needs moderating.
          if params[:community].to_s == "true"
            runs = runs.joins(:user).where(users: { is_admin: false })
          end
          runs = runs.where(restaurant_id: params[:restaurant_id]) if params[:restaurant_id].present?

          total  = runs.count
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset
          page   = runs.limit(limit).offset(offset).to_a
          counts = decision_counts_for(page)

          render json: {
            runs: page.map { |run| serialize_queue_run(run, counts[run.id] || {}) },
            pagination: { total: total, limit: limit, offset: offset }
          }
        end

        def re_extract
          run = IngestionRun.find(params[:id])
          Ingestion::ReExtractRun.call(run)
          render json: { id: run.id, status: run.status }
        rescue Ingestion::ReExtractRun::AlreadyPublished
          render json: { error: "already_published" }, status: :unprocessable_entity
        end

        private

        # One grouped query for the page, not a COUNT per run — the
        # (ingestion_run_id, decision) pair collapses into nested hashes.
        def decision_counts_for(runs)
          IngestionItem.where(ingestion_run_id: runs.map(&:id))
                       .group(:ingestion_run_id, :decision)
                       .count
                       .each_with_object({}) do |((run_id, decision), n), out|
            (out[run_id] ||= {})[decision] = n
          end
        end

        def serialize_queue_run(run, counts)
          {
            id:                run.id,
            status:            run.status,
            enrichment_status: run.enrichment_status,
            input_kind:        run.input_kind,
            failure_message:   run.failure_message,
            api_cost_cents:    run.api_cost_cents,
            created_at:        run.created_at,
            user: run.user && {
              id: run.user.id, handle: run.user.handle,
              email: run.user.email, is_admin: run.user.is_admin
            },
            restaurant: run.restaurant && {
              id: run.restaurant.id, name: run.restaurant.name,
              slug: run.restaurant.slug, status: run.restaurant.status
            },
            decision_counts: {
              pending:  counts["pending"]  || 0,
              accepted: counts["accepted"] || 0,
              rejected: counts["rejected"] || 0,
              edited:   counts["edited"]   || 0
            }
          }
        end
      end
    end
  end
end
