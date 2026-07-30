module Api
  module V1
    module Admin
      # Parent for every /api/v1/admin/* controller. Authenticated
      # non-admins get a 404 instead of a 403 — same shape as the
      # owner-or-404 precedent in IngestionRunsController#show — so a
      # response never confirms "admin-only thing here, you just can't
      # have it". Unauthenticated callers still get Devise's 401 from
      # the inherited authenticate_user!.
      class BaseController < Api::V1::BaseController
        before_action :require_admin!

        private

        def require_admin!
          return if current_user&.is_admin?

          render json: { error: "not_found" }, status: :not_found
        end
      end
    end
  end
end
