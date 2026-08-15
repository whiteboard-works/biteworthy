module Api
  module V1
    module Auth
      # POST /api/v1/auth/password → 202 (request a reset email)
      # PUT  /api/v1/auth/password → 200 (consume the token, set a new password)
      #
      # The emailed link lands on the web app's /reset-password page (see
      # app/views/devise/mailer/reset_password_instructions.*), which PUTs
      # back here with the token. JSON only — the stock controller's HTML
      # views don't exist in this API-only app, so its GET routes aren't
      # mounted (see routes.rb).
      class PasswordsController < Devise::PasswordsController
        respond_to :json

        # Always 202, found or not: a different answer per email would let
        # anyone probe which addresses have accounts. The mail itself goes
        # through the queue (User#send_devise_notification), so response
        # latency doesn't leak the answer either.
        def create
          resource_class.send_reset_password_instructions(create_params)
          head :accepted
        end

        def update
          # Devise's confirmation validation is a no-op when the field is
          # nil — a client that omits it entirely must not skip the check
          # the contract declares required.
          if update_params[:password_confirmation].blank?
            return render json: { errors: { password_confirmation: [ "can't be blank" ] } },
                          status: :unprocessable_entity
          end

          self.resource = resource_class.reset_password_by_token(update_params)
          if resource.errors.empty?
            # A reset is the remedy for a compromised account — rotate the
            # JWT revocation key so every session issued before it is dead,
            # not just the password.
            resource.update_column(:jti, SecureRandom.uuid)
            render json: { status: "password_updated" }, status: :ok
          else
            # Field-keyed, matching the registrations/omniauth 422 envelope.
            render json: { errors: resource.errors.as_json }, status: :unprocessable_entity
          end
        end

        private

        # `params.require(:user)` would escape this controller's ancestry as
        # a raw 400 (no BaseController rescue_from here) — tolerate a missing
        # or malformed `user` key and let the empty params fail validation.
        def user_scope
          raw = params[:user]
          raw.is_a?(ActionController::Parameters) ? raw : ActionController::Parameters.new({})
        end

        def create_params
          user_scope.permit(:email)
        end

        def update_params
          user_scope.permit(:reset_password_token, :password, :password_confirmation)
        end
      end
    end
  end
end
