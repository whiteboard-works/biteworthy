module Api
  module V1
    # The API half of the OAuth consent screen. The screen itself is a
    # page in apps/web — see config/initializers/doorkeeper.rb for why
    # consent cannot render here.
    #
    # `show` describes the request in words a person can act on: who is
    # asking, and what each scope actually lets them do. `create` records
    # that they approved, as a handoff token bound to this exact request.
    class OauthConsentsController < BaseController
      rescue_from Oauth::Handoff::InvalidReturnTo, with: :render_unprocessable

      before_action :verify_audience!
      before_action :verify_redirect_uri!

      def show
        render json: {
          client:       serialize_client(application),
          scopes:       requested_scopes.map { |s| { name: s, description: Tools::Scopes.describe(s) } },
          redirect_uri: authorize_params["redirect_uri"],
          state:        authorize_params["state"],
          user:         { id: current_user.id, email: current_user.email }
        }
      end

      def create
        # Approving a scope the client did not ask for, or one this server
        # does not grant, should never be possible from a page — but the
        # page is not what enforces it.
        unknown = requested_scopes.reject { |s| Tools::Scopes.valid?(s) }
        return render_error("Unknown scope(s): #{unknown.join(', ')}.") if unknown.any?

        render json: {
          redirect_to: Oauth::Handoff.resume_url_for(
            return_to: return_to, origin: public_host,
            handoff:   Oauth::Handoff.mint(user: current_user, return_to: return_to, origin: public_host)
          )
        }
      end

      private

      # RFC 8707. A client that names an audience must name ours — a
      # token minted here is not meant to be presentable elsewhere.
      # Checked at consent rather than at the token endpoint because the
      # handoff digest covers every authorize parameter, so a `resource`
      # that passed here cannot be swapped afterwards.
      def verify_audience!
        requested = authorize_params["resource"]
        return if requested.blank? || requested == "#{public_host}/mcp"

        render_error("This authorization server does not issue tokens for #{requested}.")
      end

      # Two reasons, and the second is the important one. A screen that
      # displays a destination doorkeeper would reject is lying about what
      # approval does; and the page sends a *denial* straight back to this
      # URI, which would be an open redirect if anyone could name it.
      # Doorkeeper's own checker decides, so the answer here and the answer
      # at /oauth/authorize cannot disagree.
      def verify_redirect_uri!
        requested = authorize_params["redirect_uri"]
        return if requested.present? &&
                  Doorkeeper::OAuth::Helpers::URIChecker
                    .valid_for_authorization?(requested, application.redirect_uri)

        render_error("That redirect_uri is not registered for this client.")
      end

      def return_to
        params.require(:return_to)
      end

      def authorize_params
        @authorize_params ||= Rack::Utils.parse_query(
          Oauth::Handoff.authorize_uri!(return_to, origin: public_host).query.to_s
        )
      end

      # Doorkeeper's own default when a request names no scopes.
      def requested_scopes
        scopes = authorize_params["scope"].to_s.split
        scopes.presence || Doorkeeper.config.default_scopes.to_a
      end

      def application
        @application ||= Doorkeeper::Application.find_by(uid: authorize_params["client_id"]) ||
                         raise(ActiveRecord::RecordNotFound, "Unknown client.")
      end

      def serialize_client(app)
        { name: app.name, uid: app.uid, confidential: app.confidential? }
      end

      def render_error(message, status = :unprocessable_entity)
        render json: { error: message }, status: status
      end
    end
  end
end
