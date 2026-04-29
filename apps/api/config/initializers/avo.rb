# Avo is mounted at /admin (not /avo) and gated with HTTP Basic auth
# in Phase 1.5. This is intentionally low-friction for the pre-launch
# admin team — Phase 4 (`Reviews + accounts`) swaps to Devise sessions
# tied to the `is_admin` flag once we have multiple admin users.
#
# All other settings are left at Avo defaults; the file is short on
# purpose. Reach for the upstream docs (https://docs.avohq.io) when
# we need to customize a screen.
Avo.configure do |config|
  config.root_path = "/admin"
  config.app_name  = "BiteWorthy Admin"

  # The HTTP Basic credentials live in ENV. Production must set both;
  # local dev falls back to admin/admin so a fresh clone can boot the
  # admin UI without secrets. Test runs use the same defaults so the
  # smoke spec can hit /admin with `Authorization: Basic ...`.
  config.authenticate_with do
    expected_user     = ENV.fetch("ADMIN_USERNAME", "admin")
    expected_password = ENV.fetch("ADMIN_PASSWORD", "admin")

    authenticate_or_request_with_http_basic("BiteWorthy Admin") do |user, password|
      ActiveSupport::SecurityUtils.secure_compare(user,     expected_user) &&
        ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
    end
  end

  # Authorization is left disabled — every authenticated admin can do
  # everything. Read-only restrictions on User / Suggestion are
  # enforced via `self.authorization` on the resource classes.
  config.authorization_client = nil
  config.explicit_authorization = true

  config.click_row_to_view_record = true
end
