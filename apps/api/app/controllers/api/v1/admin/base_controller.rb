module Api
  module V1
    module Admin
      # Parent for every /api/v1/admin/* controller. Authenticated
      # non-admins get the same 404 an unknown path would return, so
      # the namespace's existence is never advertised (matches the
      # owner-or-404 precedent in IngestionRunsController#show).
      # Unauthenticated callers still get Devise's 401 from the
      # inherited authenticate_user!.
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
