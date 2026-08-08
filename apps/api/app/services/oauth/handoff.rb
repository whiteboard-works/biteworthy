# frozen_string_literal: true

module Oauth
  # The bridge between doorkeeper's `/oauth/authorize` and the consent
  # screen, which lives in apps/web because that is the only place a
  # browser is signed in (see config/initializers/doorkeeper.rb).
  #
  # The problem a handoff token solves is that consent happens on a
  # different origin than the grant. Something has to carry "this person
  # approved this" back across, and it cannot be a bare user id — that
  # would let anyone holding one mint a grant for *any* client, with any
  # scopes, to any redirect URI.
  #
  # So the token is bound: it carries a digest of the exact authorize
  # parameters the person was shown. Change the client, the scopes, or the
  # redirect URI on the way back and the digest stops matching. This is the
  # same shape as the chat's confirmation fingerprint — an approval is only
  # valid for the request it was given for.
  module Handoff
    PURPOSE        = :oauth_consent
    TTL            = 5.minutes
    AUTHORIZE_PATH = "/oauth/authorize"
    PARAM          = "handoff"

    class InvalidReturnTo < StandardError; end

    class << self
      # Called by the web app once the person has approved. `origin` is
      # this server's own origin: a handoff is a signed capability, and
      # handing one to a URL on someone else's host would be giving it
      # away.
      def mint(user:, return_to:, origin:)
        verifier.generate(
          { "uid" => user.id, "bind" => binding_digest(authorize_uri!(return_to, origin: origin)) },
          purpose: PURPOSE, expires_in: TTL
        )
      end

      # doorkeeper's `resource_owner_authenticator`. Returns the user, or
      # nil to mean "send them to consent". The URL here is our own
      # request, so it needs no origin check — only the binding one.
      def resource_owner_for(request)
        token = request.params[PARAM]
        return nil if token.blank?

        payload = verifier.verified(token, purpose: PURPOSE)
        return nil if payload.blank?

        # The whole point. A handoff minted for one authorize request must
        # not issue a grant for a different one.
        return nil unless ActiveSupport::SecurityUtils.secure_compare(
          payload["bind"].to_s, binding_digest(URI.parse(request.original_url))
        )

        User.find_by(id: payload["uid"])
      end

      def consent_url_for(request)
        "#{web_origin}/oauth/consent?#{{ return_to: request.original_url }.to_query}"
      end

      # Where the browser goes after approval: the same authorize URL, now
      # carrying the handoff. Built here so the digest and the URL that
      # gets digested cannot be assembled by two different rules.
      def resume_url_for(return_to:, handoff:, origin:)
        uri = authorize_uri!(return_to, origin: origin)
        uri.query = query_of(uri).merge(PARAM => handoff).to_query
        uri.to_s
      end

      # A consent request must be for *this* server's authorize endpoint.
      # Without the origin check, minting would both sign a digest for
      # somebody else's URL and hand the resulting token to their host.
      def authorize_uri!(url, origin:)
        uri = URI.parse(url.to_s)
        raise InvalidReturnTo, "return_to must be #{origin}#{AUTHORIZE_PATH}" unless
          uri.path == AUTHORIZE_PATH && origin_of(uri) == origin.to_s.chomp("/")

        uri
      rescue URI::InvalidURIError
        raise InvalidReturnTo, "return_to is not a URL"
      end

      # The parameters that define the grant. Deliberately everything
      # except the handoff itself: naming an allow-list would mean a
      # parameter added later (a new PKCE method, an RFC 8707 `resource`)
      # silently falls outside the binding.
      def binding_digest(uri)
        Digest::SHA256.hexdigest(query_of(uri).except(PARAM).sort.to_json)
      end

      def web_origin
        ENV["WEB_ORIGIN"].to_s.split(",").map(&:strip).compact_blank.first ||
          "http://localhost:3001"
      end

      private

      def origin_of(uri)
        return nil if uri.scheme.blank? || uri.host.blank?

        port = uri.port == uri.default_port ? nil : ":#{uri.port}"
        "#{uri.scheme}://#{uri.host}#{port}"
      end

      def query_of(uri)
        Rack::Utils.parse_query(uri.query.to_s)
      end

      def verifier
        Rails.application.message_verifier(:oauth_handoff)
      end
    end
  end
end
