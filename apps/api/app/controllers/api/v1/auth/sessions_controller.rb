module Api
  module V1
    module Auth
      # POST   /api/v1/auth/login   → 200 + JWT in Authorization header
      # DELETE /api/v1/auth/logout  → 204, rotates user.jti to invalidate token
      # POST   /api/v1/auth/refresh → 200 + new JWT, rotates jti
      class SessionsController < Devise::SessionsController
        respond_to :json

        skip_before_action :verify_signed_out_user, only: [:destroy]

        # Override create so we sign in without touching the session
        # (sessions are disabled in API mode). devise-jwt's warden
        # hook still fires and adds the JWT to the response header.
        def create
          self.resource = warden.authenticate!(auth_options)
          sign_in(resource_name, resource, store: false)
          render json: { user: user_payload(resource) }, status: :ok
        end

        # Override destroy so we don't touch the session.
        def destroy
          # Revocation strategy (JTIMatcher) rotates user.jti via
          # devise-jwt's revocation_requests hook. Manually sign out
          # without session storage to keep warden tidy.
          sign_out(resource_name) if signed_in?(resource_name)
          head :no_content
        end

        # POST /api/v1/auth/refresh — bearer token in, fresh bearer
        # token out. Rotates the user's jti so the previous token is
        # dead the moment this returns.
        #
        # Manual dispatch: refresh isn't in jwt.dispatch_requests
        # because the JWT strategy needs to validate the *incoming*
        # token, and it won't run on dispatch paths.
        def refresh
          self.resource = warden.authenticate!(scope: :user)
          resource.update!(jti: SecureRandom.uuid)
          token, _ = Warden::JWTAuth::UserEncoder.new.call(resource, :user, nil)
          response.set_header("Authorization", "Bearer #{token}")
          render json: { user: user_payload(resource) }, status: :ok
        end

        private

        def user_payload(user)
          {
            id: user.id,
            email: user.email,
            handle: user.handle,
            display_name: user.display_name
          }
        end
      end
    end
  end
end
