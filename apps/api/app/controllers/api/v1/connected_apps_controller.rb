module Api
  module V1
    # The OAuth grants a person has handed out, and the one way to take
    # one back.
    #
    # M8 shipped the authorization server with `skip_controllers
    # :authorized_applications`, which removed doorkeeper's own management
    # UI along with its login-dependent scaffolding — leaving approval as
    # a one-way door. An access token expires in two hours, but the
    # refresh chain behind it does not expire at all, so "wait it out" was
    # never a revocation story. This is the missing half.
    #
    # Revoking is per-application and covers both tokens and grants: a
    # client holding an unexchanged authorization code must not be able to
    # walk back in a second after being cut off.
    class ConnectedAppsController < BaseController
      def index
        render json: { apps: authorized_applications.map { |app| serialize(app) } }
      end

      def destroy
        app = authorized_applications.find_by(id: params[:id])
        # Scoped to this user's own grants, so an id belonging to someone
        # else's connection is indistinguishable from one that never
        # existed — the same shape `mcp_tokens#destroy` has.
        return render json: { error: "No such connected app." }, status: :not_found if app.nil?

        Doorkeeper::Application.revoke_tokens_and_grants_for(app.id, current_user)
        head :no_content
      end

      private

      # `authorized_for` selects on `revoked_at IS NULL` and deliberately
      # not on expiry — which is what makes it right here. Access tokens
      # last two hours; the grant behind one lasts until it is revoked,
      # because the client refreshes. Filtering on "unexpired" would empty
      # this list two hours after every connection and tell people they
      # had disconnected apps that were still reading their profile.
      def authorized_applications
        Doorkeeper::Application.authorized_for(current_user).order(:created_at)
      end

      def serialize(app)
        tokens = live_tokens[app.id] || []
        scopes = tokens.flat_map { |token| token.scopes.to_a }.uniq.sort

        {
          id:              app.id,
          name:            app.name,
          scopes:          scopes,
          # The sentences the consent screen showed, so the list reads the
          # same way the approval did rather than as opaque slugs.
          scope_details:   scopes.map { |scope| { scope: scope, description: Tools::Scopes.describe(scope) } },
          connected_at:    tokens.map(&:created_at).min&.iso8601,
          last_renewed_at: tokens.map(&:created_at).max&.iso8601
        }
      end

      # One query for every application rather than one per row.
      def live_tokens
        @live_tokens ||= Doorkeeper::AccessToken.active_for(current_user).group_by(&:application_id)
      end
    end
  end
end
