module Api
  module V1
    # POST /api/v1/waitlist_signups
    #   { waitlist_signup: { email:, source: } }
    #
    # Phase 5.10 — soft-launch waitlist endpoint.
    #
    # Public + unauthenticated (it's a marketing-page form). Returns
    # 200 on both new and duplicate emails so a re-submitter doesn't
    # leak whether the address was already in the list (and so the
    # form just says "thanks" either way).
    #
    # 422 only on a malformed email (regex fails).
    class WaitlistSignupsController < BaseController
      skip_before_action :authenticate_user!, only: [:create]

      def create
        signup = WaitlistSignup.find_or_initialize_by(email: normalized_email)
        signup.source = params.dig(:waitlist_signup, :source) || "landing"

        if signup.persisted?
          # Re-submit — silently no-op (no second confirmation mail).
          render json: { ok: true, duplicate: true }, status: :ok
          return
        end

        if signup.save
          # Best-effort send; Postmark queueing failures shouldn't
          # block the response (the user is already on the list).
          WaitlistMailer.confirm(signup.id).deliver_later rescue nil
          render json: { ok: true, duplicate: false }, status: :ok
        else
          render json: { ok: false, errors: signup.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def normalized_email
        params.dig(:waitlist_signup, :email).to_s.strip.downcase
      end
    end
  end
end
