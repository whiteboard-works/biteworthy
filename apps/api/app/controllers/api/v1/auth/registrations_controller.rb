module Api
  module V1
    module Auth
      # POST /api/v1/auth/signup → 201 + JWT in Authorization header
      class RegistrationsController < Devise::RegistrationsController
        respond_to :json

        before_action :configure_permitted_parameters

        # Override Devise's create to avoid the automatic sign_up flow
        # that writes to the session — sessions are disabled in API
        # mode. We still need to call sign_in (with store: false) so
        # devise-jwt's warden hook dispatches a token in the response
        # Authorization header.
        def create
          # Legal remediation E4 — age gate. The client must affirm the
          # 13+ minimum (COPPA; Privacy Policy + ToS). We record only the
          # affirmation time, never a birth date.
          unless ActiveModel::Type::Boolean.new.cast(params.dig(:user, :age_confirmation))
            return render json: {
              errors: { age_confirmation: ["You must confirm you are at least 13 years old."] }
            }, status: :unprocessable_entity
          end

          build_resource(sign_up_params)
          resource.age_confirmed_at = Time.current

          if resource.save
            sign_in(resource_name, resource, store: false)
            render json: { user: user_payload(resource) }, status: :created
          else
            clean_up_passwords(resource)
            render json: { errors: resource.errors.as_json }, status: :unprocessable_entity
          end
        end

        private

        def configure_permitted_parameters
          devise_parameter_sanitizer.permit(
            :sign_up,
            keys: [:handle, :display_name]
          )
        end

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
