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
        respond_to :json

        # Skip CSRF protection on the callback — the provider's
        # redirect doesn't carry our CSRF token, and OAuth's `state`
        # parameter (validated by the strategy) is the actual
        # cross-site forgery defense for this leg.
        skip_before_action :verify_authenticity_token, raise: false

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

          # Mint a JWT. This is the same code path devise-jwt uses for
          # the dispatch hook on signup/login — UserEncoder reads
          # `jwt.expiration_time` and `jwt.secret` from the initializer.
          token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
          response.set_header("Authorization", "Bearer #{token}")

          render json: { user: user_payload(user) }, status: :ok
        end

        def user_payload(user)
          {
            id: user.id,
            email: user.email,
            handle: user.handle,
            display_name: user.display_name,
            provider: user.provider
          }
        end
      end
    end
  end
end
