module Api
  module V1
    module Admin
      # GET /api/v1/admin/dashboard — Ingestion::CostMetrics buckets +
      # the community counters + queue counts for the web admin
      # (successor to the Phase 2.9 ERB dashboard, retired with Avo).
      class DashboardsController < BaseController
        def show
          render json: {
            target_cents_per_item: Ingestion::CostMetrics::TARGET_CENTS_PER_ITEM,
            periods: Ingestion::CostMetrics.by_period.transform_values(&:to_h),
            community: community_counters,
            queues: queue_counts
          }
        end

        private

        # Same UTC-day window the Phase 6.1 cost ceiling enforces, so
        # "spend today" is exactly the number the 503 guard compares
        # against. (Parens required: an endless range at end-of-line
        # parses the NEXT line as its end.)
        def community_counters
          today_utc = (Time.current.utc.beginning_of_day..)

          {
            runs_today: IngestionRun.joins(:user)
                                    .where(users: { is_admin: false })
                                    .where(created_at: today_utc)
                                    .count,
            spend_today_cents: IngestionRun.where(created_at: today_utc).sum(:api_cost_cents),
            ceiling_cents: Integer(ENV.fetch(
              "INGESTION_DAILY_COST_CEILING_CENTS",
              ::Ingestion::StartRun::DAILY_COST_CEILING_CENTS_DEFAULT
            ))
          }
        end

        # All four are cheap indexed counts (partial index on flagged
        # reviews, status columns elsewhere).
        def queue_counts
          {
            flagged_reviews: Review.awaiting_moderation.count,
            pending_suggestions: Suggestion.where(status: "pending").count,
            community_published_restaurants: Restaurant.community_published.count,
            # `.kept` — this is a queue depth, and an archived run is
            # one an admin has already dealt with. Spend figures above
            # deliberately do not filter: archiving does not refund.
            staged_runs: IngestionRun.kept.where(status: "staged").count
          }
        end
      end
    end
  end
end
