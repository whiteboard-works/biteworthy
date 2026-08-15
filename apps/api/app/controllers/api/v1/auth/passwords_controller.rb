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
        # anyone probe which addresses have accounts. The mail only goes
        # out when the account exists.
        def create
          resource_class.send_reset_password_instructions(create_params)
          head :accepted
        end

        def update
          self.resource = resource_class.reset_password_by_token(update_params)
          if resource.errors.empty?
            render json: { status: "password_updated" }, status: :ok
          else
            render json: { errors: resource.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def create_params
          params.require(:user).permit(:email)
        end

        def update_params
          params.require(:user).permit(:reset_password_token, :password, :password_confirmation)
        end
      end
    end
  end
end
