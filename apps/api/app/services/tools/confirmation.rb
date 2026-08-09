# frozen_string_literal: true

module Tools
  # A signed "a person said yes to exactly this call" grant.
  #
  # The gate itself is declared on the tool (`confirm_when` /
  # `confirmation_prompt`) and was, until this existed, read only by
  # `Chat::AgentLoop`. That made it a property of one front door: an MCP
  # client holding `profile:write` could remove an allergen from someone's
  # avoid list with nothing asked, while the same call through the chat
  # parked and waited. `Tools::Base` says it is the one place a call is
  # authorized "for both front doors"; this is what makes that true of
  # confirmation too.
  #
  # **Bound to the call, not to the tool.** The grant carries a digest of
  # the tool name, the arguments, and the caller — so an approval for
  # "stop avoiding peanut" cannot be replayed against "stop avoiding
  # peanut and shellfish", and one person's approval is not another's.
  # Same principle as the chat's fingerprint and `Oauth::Handoff`.
  module Confirmation
    PURPOSE = :tool_confirmation
    TTL     = 10.minutes

    class << self
      # Minted by whoever actually got the answer: the chat, once the
      # person taps approve, and nothing else. A model never mints one —
      # it can only carry back the token the server handed it.
      def mint(tool:, args:, user_id:)
        verifier.generate({ "d" => digest(tool: tool, args: args, user_id: user_id) },
                          purpose: PURPOSE, expires_in: TTL)
      end

      def satisfied?(token, tool:, args:, user_id:)
        return false if token.blank?

        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return false if payload.blank?

        ActiveSupport::SecurityUtils.secure_compare(
          payload["d"].to_s, digest(tool: tool, args: args, user_id: user_id)
        )
      end

      private

      # Sorted and string-keyed, because the same call has to digest the
      # same way whether it arrived as JSON over MCP or as symbols from
      # the agent loop — and because jsonb does not preserve key order, so
      # anything derived from a stored row would not reliably match.
      #
      # `confirmation` itself is excluded: it is the answer, not part of
      # the question, and including it would make every grant unusable the
      # moment it was presented.
      def digest(tool:, args:, user_id:)
        canonical = args.to_h
                        .transform_keys(&:to_s)
                        .except("confirmation")
                        .sort
        Digest::SHA256.hexdigest(JSON.generate([tool.to_s, canonical, user_id.to_s]))
      end

      def verifier = Rails.application.message_verifier(PURPOSE)
    end
  end
end
