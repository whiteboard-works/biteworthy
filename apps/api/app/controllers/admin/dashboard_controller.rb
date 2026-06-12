module Admin
  # Phase 2.9 cost + latency dashboard at /admin/dashboard.
  #
  # Hand-rolled instead of an Avo Pro Dashboard (Community license
  # only — see Phase 1.5). Mounted at the same `/admin` prefix and
  # gated by the same HTTP Basic credentials Avo uses, so navigating
  # in from `/admin` is seamless.
  #
  # Inherits from ActionController::Base (not ::API) because we
  # render an ERB template; the rest of the app stays api_only.
  class DashboardController < ActionController::Base
    layout false # keep it self-contained — no app-wide layout file

    protect_from_forgery with: :exception

    before_action :require_admin_basic_auth!

    def index
      @metrics       = Ingestion::CostMetrics.by_period
      @target_target = Ingestion::CostMetrics::TARGET_CENTS_PER_ITEM

      # Phase 6.4 — community-ingestion counters. Same UTC-day window
      # the Phase 6.1 cost ceiling enforces, so "spend today" here is
      # exactly the number the 503 guard compares against.
      # (Parens required: an endless range at end-of-line parses the
      # NEXT line as its end — bit me once already.)
      today_utc             = (Time.current.utc.beginning_of_day..)
      @community_runs_today = IngestionRun.joins(:user)
                                          .where(users: { is_admin: false })
                                          .where(created_at: today_utc)
                                          .count
      @spend_today_cents    = IngestionRun.where(created_at: today_utc).sum(:api_cost_cents)
      @ceiling_cents        = Integer(ENV.fetch(
        "INGESTION_DAILY_COST_CEILING_CENTS",
        Api::V1::IngestionRunsController::DAILY_COST_CEILING_CENTS_DEFAULT
      ))
    end

    private

    # Reuses the same env vars the Avo initializer reads (Phase 1.5).
    # Keeping the gate logic local to this controller — Avo doesn't
    # expose a "run my own request through your auth check" hook in
    # Community, so we duplicate the few lines here.
    def require_admin_basic_auth!
      expected_user     = ENV.fetch("ADMIN_USERNAME", "admin")
      expected_password = ENV.fetch("ADMIN_PASSWORD", "admin")

      authenticate_or_request_with_http_basic("BiteWorthy Admin") do |user, password|
        ActiveSupport::SecurityUtils.secure_compare(user,     expected_user) &&
          ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
      end
    end
  end
end
