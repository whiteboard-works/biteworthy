# frozen_string_literal: true

module Tools
  # Who is calling, resolved once per request from the MCP server_context.
  #
  # `public_host` rides along so tools can build signed ActiveStorage URLs
  # the same way Api::V1::BaseController does.
  class Context
    # `user_id` is readable without touching the database: a confirmation
    # grant binds to whoever the credential names, and it must not cost a
    # user lookup to decide whether a call needs one.
    attr_reader :user_id, :public_host, :request_id, :scopes

    # `Registry.for`'s memo. It lives here because a context is the unit
    # the filtered catalogue is constant over; see the comment there.
    attr_accessor :cached_tools

    def initialize(server_context = nil)
      raw          = server_context || {}
      @user_id     = raw[:user_id]
      @public_host = raw[:public_host]
      @request_id  = raw[:request_id]
      # What this caller's credential is allowed to touch.
      #
      # **Not saying and saying nothing are different answers**, and the
      # fail-open this replaced could not tell them apart. Omitting the
      # key means no credential is narrowing this call at all — an
      # in-process caller, a session — so it is unrestricted. Passing the
      # key with an empty list means a credential was consulted and
      # granted nothing, which is a refusal.
      #
      # That distinction is the whole fix: `granted_scopes` and an
      # `McpToken` always *state* their grant, so a grant that comes out
      # empty now fails closed instead of quietly reaching the taxonomy
      # and the moderation queue. See `Scopes::ALL`.
      @scopes      = raw.key?(:scopes) ? Array(raw[:scopes]) : [ Scopes::ALL ]
    end

    def user
      return @user if defined?(@user)
      @user = @user_id ? User.find_by(id: @user_id) : nil
    end

    def signed_in?   = !user.nil?
    def admin?       = !!user&.is_admin
    def super_admin? = !!user&.is_super_admin

    # Whether this caller's destructive tool calls run without parking for
    # a human answer. Read here rather than in `Tools::Base` so both front
    # doors resolve it from the same place the audience check does.
    def skip_confirmations? = !!user&.skip_confirmations

    def user!
      user || raise(Errors::Unauthorized)
    end

    def admin!
      raise Errors::Unauthorized unless signed_in?
      raise Errors::Forbidden unless admin?
      user
    end
  end
end
