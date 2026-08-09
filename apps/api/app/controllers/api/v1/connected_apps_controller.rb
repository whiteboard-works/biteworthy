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
        # What the app can do *now*, which is what someone is deciding
        # about — not the union of everything ever approved. Re-approving
        # with narrower scope should show the narrower answer.
        scopes = tokens.flat_map { |token| token.scopes.to_a }.uniq.sort

        {
          id:              app.id,
          name:            app.name,
          # Registration is unauthenticated (RFC 7591), so a name is a
          # claim, not an identity: two registrations can both call
          # themselves "Claude Desktop" and one of them can be hostile.
          # The consent screen answers this by showing the destination
          # alongside the name, and a list you revoke from has to be at
          # least as decidable as the screen you approved on.
          redirect_host:   redirect_host_for(app),
          scopes:          scopes,
          # The sentences the consent screen showed, so the list reads the
          # same way the approval did rather than as opaque slugs.
          scope_details:   scopes.map { |scope| { scope: scope, description: Tools::Scopes.describe(scope) } },
          connected_at:    approved_at[app.id]&.iso8601 || tokens.map(&:created_at).min&.iso8601,
          last_renewed_at: tokens.map(&:created_at).max&.iso8601
        }
      end

      # A client may register several redirect URIs; the host is what
      # distinguishes one registration from another, and repeating all of
      # them would bury it.
      def redirect_host_for(app)
        hosts = app.redirect_uri.to_s.split.filter_map do |uri|
          URI.parse(uri).host
        rescue URI::InvalidURIError
          nil
        end

        hosts.uniq.join(", ").presence
      end

      # **Not** the oldest live token. `previous_refresh_token` exists on
      # the tokens table, so `refresh_token_revoked_on_use?` is true and
      # doorkeeper revokes the prior row the first time a refreshed token
      # is used — after a week of two-hourly refreshes only the newest row
      # survives, and "oldest live token" would render a week-old grant as
      # "Connected today".
      #
      # A grant row is written only by `/oauth/authorize`, never by a
      # refresh, so the newest one is the last time a person actually
      # approved this app. Newest rather than oldest because disconnecting
      # and reconnecting is a new connection, not a continuation.
      def approved_at
        @approved_at ||= Doorkeeper::AccessGrant
                         .where(resource_owner_id: current_user.id)
                         .group(:application_id)
                         .maximum(:created_at)
      end

      # One query for every application rather than one per row.
      def live_tokens
        @live_tokens ||= Doorkeeper::AccessToken.active_for(current_user).group_by(&:application_id)
      end
    end
  end
end
