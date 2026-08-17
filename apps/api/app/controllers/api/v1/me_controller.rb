module Api
  module V1
    # GET /api/v1/me — the caller's own identity payload.
    #
    # Exists so clients can re-read the user (notably `is_admin`, which
    # gates the web /admin shell) without POST /api/v1/auth/refresh —
    # refresh rotates the jti and would invalidate the user's other
    # sessions if used as a read probe.
    #
    # PATCH /api/v1/me — self-service account edits. Only `handle` for
    # now: it was previously settable at signup and then frozen forever,
    # which stranded every auto-generated `diner_<hex>` account. Errors
    # come back per-field ({ errors: { handle: [...] } }) like the auth
    # endpoints, so clients can render "already taken" inline.
    class MeController < BaseController
      include AuthTokenResponse

      def show
        render json: { user: user_payload(current_user) }
      end

      def update
        attrs = params.permit(:handle)

        # An empty body (or one whose only fields permit filtered out)
        # would otherwise 200 as a silent no-op that reads as a saved
        # change. Mirrors the admin endpoint's empty-attrs refusal, in
        # this endpoint's per-field error shape.
        unless attrs.key?(:handle)
          render json: { errors: { base: [ "no supported fields" ] } },
                 status: :unprocessable_entity
          return
        end

        if current_user.update(attrs)
          render json: { user: user_payload(current_user) }
        else
          render json: { errors: current_user.errors.as_json }, status: :unprocessable_entity
        end
      end
    end
  end
end
