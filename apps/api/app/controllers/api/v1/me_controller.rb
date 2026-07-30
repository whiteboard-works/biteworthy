module Api
  module V1
    # GET /api/v1/me — the caller's own identity payload.
    #
    # Exists so clients can re-read the user (notably `is_admin`, which
    # gates the web /admin shell) without POST /api/v1/auth/refresh —
    # refresh rotates the jti and would invalidate the user's other
    # sessions if used as a read probe.
    class MeController < BaseController
      include AuthTokenResponse

      def show
        render json: { user: user_payload(current_user) }
      end
    end
  end
end
