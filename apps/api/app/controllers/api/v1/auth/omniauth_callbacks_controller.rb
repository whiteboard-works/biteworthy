module Api
  module V1
    module Auth
      # GET /api/v1/auth/:provider           → OmniAuth start (handled by Devise/OmniAuth)
      # GET /api/v1/auth/:provider/callback  → here. Issues a JWT in the Authorization header.
      #
      # Mobile + web clients open the start URL in an in-app browser
      # (or system browser); the provider redirects back to the
      # callback with an auth hash; this controller mints a JWT and
      # responds with JSON. There's no session — JWT is the only
      # piece of state on the client.
      class OmniauthCallbacksController < Devise::OmniauthCallbacksController
        include AuthTokenResponse

        respond_to :json

        # No `skip_before_action :verify_authenticity_token` needed:
        # ApplicationController extends ActionController::API
        # (config.api_only = true), which never installs CSRF
        # protection. OAuth's own `state` parameter — validated by the
        # OmniAuth strategy before we run — is the cross-site forgery
        # defense for the callback leg.

        def google_oauth2
          handle_oauth_callback
        end

        def apple
          handle_oauth_callback
        end

        # OmniAuth.config.on_failure routes here. Renders 401 + a JSON
        # error body so mobile/web don't have to parse a Devise flash.
        def failure
          render json: { error: failure_message || "authentication_failed" },
                 status: :unauthorized
        end

        private

        def handle_oauth_callback
          auth = request.env["omniauth.auth"]
          if auth.blank?
            render json: { error: "missing_omniauth_payload" }, status: :unauthorized
            return
          end

          user = User.from_omniauth(auth)

          unless user.persisted?
            render json: { errors: user.errors.as_json }, status: :unprocessable_entity
            return
          end

          # Mint a JWT — the same code path devise-jwt uses for the
          # dispatch hook on signup/login.
          attach_jwt_header(user)

          render json: { user: user_payload(user, include_provider: true) }, status: :ok
        end
      end
    end
  end
end
