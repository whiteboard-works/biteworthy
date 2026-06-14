module Api
  module V1
    module Auth
      # POST /api/v1/auth/signup → 201 + JWT in Authorization header
      class RegistrationsController < Devise::RegistrationsController
        respond_to :json

        before_action :configure_permitted_parameters
        before_action :authenticate_user!, only: [:destroy]

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

          # Clickwrap assent — the client must affirmatively agree to the
          # Terms + Privacy Policy. Recorded as terms_accepted_at, which
          # is what makes the ToS (incl. arbitration + class waiver)
          # enforceable rather than weak browsewrap.
          unless ActiveModel::Type::Boolean.new.cast(params.dig(:user, :terms_acceptance))
            return render json: {
              errors: { terms_acceptance: ["You must agree to the Terms of Service and Privacy Policy."] }
            }, status: :unprocessable_entity
          end

          build_resource(sign_up_params)
          resource.age_confirmed_at = Time.current
          resource.terms_accepted_at = Time.current

          if resource.save
            sign_in(resource_name, resource, store: false)
            render json: { user: user_payload(resource) }, status: :created
          else
            clean_up_passwords(resource)
            render json: { errors: resource.errors.as_json }, status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/auth/signup — permanently deletes the caller's
        # account. Legal remediation E2 (Privacy Policy "Delete your
        # account"). Routes the delete through the ORM so the model's
        # `dependent:` rules run — the FKs have no ON DELETE CASCADE, so
        # a raw DB delete would either orphan rows or violate a
        # constraint. Personal records are destroyed; shared menu-graph
        # rows are nullified (see User associations). The JWT is
        # invalidated implicitly — its `jti`/`sub` no longer match any
        # user once the row is gone.
        def destroy
          current_user.destroy!
          head :no_content
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
