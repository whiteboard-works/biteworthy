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

    before_action :require_admin_basic_auth!

    def index
      @metrics       = Ingestion::CostMetrics.by_period
      @target_target = Ingestion::CostMetrics::TARGET_CENTS_PER_ITEM
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
