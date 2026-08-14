module Api
  module V1
    # Least-privilege credentials for MCP clients, managed by their owner.
    #
    # The rake task that shipped with `McpToken` works for whoever has a
    # shell on the box; this is for everyone else. Connecting Claude Code
    # should not require a terminal.
    #
    # **The secret is returned exactly once**, by `create`. Nothing stored
    # can reproduce it, so `index` never carries it and there is no
    # endpoint that could.
    class McpTokensController < BaseController
      def index
        render json: {
          tokens: current_user.mcp_tokens.active.order(:created_at).map { |t| serialize(t) },
          scopes: Tools::Scopes.available,
          # Named here so the UI can offer full access as a chip like any
          # other rather than hardcoding the wildcard — the same reason
          # `scopes` is returned at all.
          full_access_scope: Tools::Scopes::ALL
        }
      end

      def create
        name = params[:name].to_s.strip
        return render_error("Give the token a name so you can tell them apart.") if name.blank?

        scopes = Array(params[:scopes]).map(&:to_s).compact_blank
        # `compact_blank` is why this cannot be left to the model alone:
        # `scopes: ["", "  "]` is a client asking for a narrow grant and
        # arriving here as `[]`, which used to mean full access to all
        # thirteen gated domains. Refusing it names the choice instead.
        if scopes.empty?
          return render_error(
            "Pick at least one scope, or send \"#{Tools::Scopes::ALL}\" to grant full access."
          )
        end

        unknown = scopes.reject { |s| Tools::Scopes.valid?(s) }
        return render_error("Unknown scope(s): #{unknown.join(', ')}.") if unknown.any?

        if current_user.mcp_tokens.active.count >= McpToken::MAX_ACTIVE
          return render_error("You already have #{McpToken::MAX_ACTIVE} active tokens. Revoke one first.")
        end

        token, secret = McpToken.issue!(user: current_user, name: name, scopes: scopes)
        # The one and only time this value exists anywhere it can be read.
        render json: serialize(token).merge(secret: secret), status: :created
      end

      def destroy
        token = current_user.mcp_tokens.active.find_by(id: params[:id])
        return render_error("No such token.", :not_found) if token.nil?

        token.revoke!
        head :no_content
      end

      private

      def serialize(token)
        {
          id:           token.id,
          name:         token.name,
          scopes:       token.scopes,
          created_at:   token.created_at.iso8601,
          last_used_at: token.last_used_at&.iso8601
        }
      end

      def render_error(message, status = :unprocessable_entity)
        render json: { error: message }, status: status
      end
    end
  end
end
