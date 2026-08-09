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

    def initialize(server_context = nil)
      raw          = server_context || {}
      @user_id     = raw[:user_id]
      @public_host = raw[:public_host]
      @request_id  = raw[:request_id]
      # What this caller's credential is allowed to touch. Empty means
      # unrestricted, which is what a session or a plain JWT is — the
      # scope check only narrows, it never grants.
      @scopes      = Array(raw[:scopes])
    end

    def user
      return @user if defined?(@user)
      @user = @user_id ? User.find_by(id: @user_id) : nil
    end

    def signed_in? = !user.nil?
    def admin?     = !!user&.is_admin

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
