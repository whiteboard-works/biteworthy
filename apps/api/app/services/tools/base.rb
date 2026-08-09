# frozen_string_literal: true

# The tool layer is the primary design surface for Biteworthy's domain
# operations. Every tool here is reachable two ways:
#
#   * over MCP, via McpController (Claude Desktop / Claude Code), and
#   * from the first-party chat's agent loop.
#
# Authorization, validation, and result shaping therefore live in the tool
# — never in a caller — so the two front doors cannot diverge.
#
# Subclasses implement `self.perform(context:, **args)` rather than
# `self.call`. Base.call owns the plumbing: it resolves the caller, enforces
# the tool's audience, translates domain errors into `isError` responses the
# model can recover from, and JSON-encodes the payload.
module Tools
  class Base < MCP::Tool
    MAX_OFFSET = 10_000

    class << self
      # Which callers may see this tool at all. Registry filters on this, so
      # a non-admin's `tools/list` never *mentions* admin tools — rejecting
      # at call time would still leak that they exist, and a listed-but-
      # forbidden tool just burns the model's turns.
      #
      #   :public — anyone, signed in or not
      #   :user   — any signed-in user
      #   :admin  — users.is_admin only
      #
      # Walks the superclass chain deliberately: Ruby does not inherit
      # class-level instance variables, so a domain base class that declares
      # `audience :user` would otherwise leave every subclass at the
      # :public default — listing write tools to anonymous callers.
      def audience(value = nil)
        @audience = value if value
        return @audience if @audience

        superclass.respond_to?(:audience) ? superclass.audience : :public
      end

      # What to show a person while this runs — "Reading the menu at
      # Nini's", not `get_menu`.
      #
      # Declared by the tool and never model-supplied: the progress line is
      # the one piece of UI a user reads while they cannot see anything
      # else, and a model narrating its own tool calls would be describing
      # what it intends rather than what is happening.
      #
      # Returns nil when a tool declares nothing, and the client falls back
      # to the humanized name.
      def running_description(&block)
        if block
          @running_description = block
          return block
        end
        return @running_description if defined?(@running_description) && @running_description

        superclass.respond_to?(:running_description) ? superclass.running_description : nil
      end

      def running_description_for(args = {})
        running_description&.call(args)
      rescue StandardError => e
        Rails.logger.error("[tools] #{name_value} running_description raised: #{e.class}: #{e.message}")
        nil
      end

      # A call a human has to approve before it runs.
      #
      # `destructive_hint` covers a tool that is always dangerous. This
      # covers one that is dangerous only for certain arguments, which is
      # the case that forced it: adding an avoid must stay frictionless,
      # and removing one un-hides dishes for someone who told us not to
      # show them.
      #
      # Walks the superclass chain for the same reason `audience` does —
      # Ruby does not inherit class-level ivars, and the last time that was
      # missed a domain base's declaration silently did nothing.
      def confirm_when(&block)
        if block
          @confirm_when = block
          return block
        end
        return @confirm_when if defined?(@confirm_when) && @confirm_when

        superclass.respond_to?(:confirm_when) ? superclass.confirm_when : nil
      end

      # The sentence the user actually approves. Declared here rather than
      # composed by the model: what someone is agreeing to must not be
      # phrased by the thing asking for the agreement.
      def confirmation_prompt(&block)
        if block
          @confirmation_prompt = block
          return block
        end
        return @confirmation_prompt if defined?(@confirmation_prompt) && @confirmation_prompt

        superclass.respond_to?(:confirmation_prompt) ? superclass.confirmation_prompt : nil
      end

      def requires_confirmation?(args = {})
        return true if annotations_value&.destructive_hint == true

        gated_by_arguments?(args)
      end

      # The narrower half, and the only half `Tools::Base` enforces
      # itself.
      #
      # `destructive_hint` is a static annotation, which means an MCP
      # client can already read it and put a human in front of the call —
      # Claude Desktop and Claude Code both do. Re-asking on the server
      # would buy a second round-trip and no extra safety.
      #
      # An argument-dependent gate is the case no annotation can express,
      # and `update_avoid_lists` is exactly it: the tool declares
      # `destructive_hint: false` so that *adding* an avoid stays
      # frictionless, which tells every client the call is safe. It is,
      # until the arguments say `remove_ingredients`. Only the server
      # knows that, so only the server can ask.
      # Fails CLOSED. The block is author-written and runs against
      # model-shaped arguments, so it can raise on a shape nobody
      # anticipated — and the other caller, `Chat::AgentLoop`, has no
      # rescue around it, so a raise there takes down the turn *before*
      # anything is parked. Asking an unnecessary question is a bad turn;
      # skipping a necessary one is someone eating something that hurts
      # them.
      def gated_by_arguments?(args = {})
        gate = confirm_when
        return false unless gate

        !!gate.call(args)
      rescue StandardError => e
        Rails.logger.error("[tools] #{name_value} confirm_when raised: #{e.class}: #{e.message}")
        true
      end

      # A tool that declares a gate advertises the argument that satisfies
      # it. Leaving it out worked only by accident: the MCP server
      # validates the model's input against this schema before dispatch,
      # and `update_avoid_lists` happens not to declare
      # `additionalProperties: false`. The first gated tool that did —
      # which `Base` explicitly recommends for `**args` tools — would have
      # had its own confirmation rejected as an unknown property, leaving
      # the model looping on `confirmation_required` with no way out.
      def input_schema_value
        declared = super
        return declared unless confirm_when

        @gated_input_schema ||= MCP::Tool::InputSchema.new(with_confirmation_property(declared.to_h))
      end

      # nil when the tool declares nothing — the client falls back to its
      # generic "allow this?" rather than us inventing a sentence here.
      def confirmation_prompt_for(args = {})
        confirmation_prompt&.call(args)
      rescue StandardError => e
        Rails.logger.error("[tools] #{name_value} confirmation_prompt raised: #{e.class}: #{e.message}")
        nil
      end

      # The one place a tool call is authorized, validated, dispatched, and
      # rescued — for both front doors. Anything that only guards one of them
      # is a divergence waiting to happen, which is the failure this layer
      # exists to prevent.
      #
      # Nothing here raises. A malformed call the model can fix comes back as
      # a recoverable `isError` response naming what was wrong; a bug in a
      # tool comes back as `tool_failed`, which tells the model to stop
      # retrying rather than to correct its arguments.
      def call(server_context: nil, confirmation: nil, **args)
        context = Context.new(server_context)
        enforce_audience!(context)
        enforce_scope!(context)
        validate_arguments!(args)
        gate = confirmation_gate(context, args, confirmation)
        return gate if gate

        perform(context: context, **args)
      rescue Errors::Error => e
        error(e.message, code: e.code)
      rescue ActiveRecord::RecordNotFound => e
        error(e.message, code: "not_found")
      rescue ActiveRecord::RecordInvalid => e
        error(e.record.errors.full_messages.to_sentence, code: "invalid")
      rescue StandardError => e
        # A tool bug must not kill a conversation or 500 an MCP client, but it
        # must not read as a recoverable domain error either — otherwise the
        # model rewrites its arguments and calls the broken tool again.
        Rails.logger.error("[tools] #{name_value} raised: #{e.class}: #{e.message}")
        Rails.error.report(e, handled: true, context: { tool: name_value })
        error("#{name_value} failed and cannot be retried.", code: "tool_failed")
      end

      def perform(context:, **args)
        raise NotImplementedError, "#{name} must implement .perform"
      end

      private

      # Never required: the whole point is that the first call arrives
      # without one and is told what to ask.
      def with_confirmation_property(schema)
        schema = schema.dup
        schema[:properties] = (schema[:properties] || {}).merge(
          confirmation: {
            type: "string",
            description: "The token from a previous confirmation_required response, after the " \
                         "user agreed to the sentence it carried. Never invent one."
          }
        )
        schema
      end

      # Returns a response when the call needs a human and does not yet
      # have one, nil when it may proceed.
      #
      # Ordered after validation on purpose: asking someone to approve a
      # call that would fail on its arguments anyway spends their
      # attention on nothing, and attention is the whole resource a
      # confirmation gate is spending.
      #
      # The chat parks *before* it gets here and mints a grant once the
      # person approves, so this is the same check on both doors rather
      # than a second one. Over MCP there is nowhere to park — a stateless
      # transport cannot ask the client a question mid-call — so the
      # refusal carries the sentence and a token, and the model has to
      # come back with an answer to it.
      def confirmation_gate(context, args, confirmation)
        return nil unless gated_by_arguments?(args)
        return nil if context.skip_confirmations?
        return nil if Confirmation.satisfied?(confirmation, tool: name_value, args: args,
                                                            user_id: context.user_id)

        prompt = confirmation_prompt_for(args) ||
                 "Confirm this #{name_value.humanize.downcase} before it runs."

        error(
          "#{prompt} This has not been confirmed yet. Ask the user in these words, and if they " \
          "agree, call #{name_value} again with the same arguments plus " \
          "confirmation: \"<the token below>\". Do not call it again if they decline.",
          code: "confirmation_required",
          confirmation_token: Confirmation.mint(tool: name_value, args: args, user_id: context.user_id),
          prompt: prompt
        )
      end

      # The LLM is an untrusted caller. It invents argument names, passes a
      # string where a number belongs, and drops required fields — none of
      # which is malice, all of which used to surface as `ArgumentError:
      # unknown keyword`. Through the chat that became "cannot be retried",
      # which is a lie: the model could have fixed it in one round.
      #
      # Two sources, because neither subsumes the other: the JSON Schema
      # knows types and required-ness, and only the Ruby signature knows
      # which keywords `perform` will actually accept. (A tool whose
      # `perform` takes `**args` has no signature to check, which is why
      # those declare `additionalProperties: false` and let the schema do
      # it — see `accepted_keywords`.)
      #
      # Every problem at once, not the first one: a model that invented an
      # argument name AND omitted a required one should fix both on the next
      # round rather than spending a tool call per mistake.
      def validate_arguments!(args)
        problems = unknown_keyword_problems(args) + schema_problems(args)
        return if problems.empty?

        raise Errors::InvalidArgument, problems.join(" ")
      end

      def unknown_keyword_problems(args)
        return [] if accepted_keywords == :any

        unknown = args.keys.map(&:to_sym) - accepted_keywords
        return [] if unknown.empty?

        ["Unknown argument(s): #{unknown.join(', ')}. #{name_value} accepts: " \
         "#{accepted_keywords.join(', ').presence || 'no arguments'}."]
      end

      # Required-ness and types both come from the schema, deliberately —
      # a second missing-arguments check here just says the same thing in
      # different words, and two sayings of one problem is context the
      # model has to spend tokens reconciling.
      def schema_problems(args)
        input_schema_value.validate_arguments(args)
        []
      rescue MCP::Tool::InputSchema::ValidationError => e
        [e.message]
      end

      # `:any` for a tool whose `perform` takes `**args` — its signature
      # cannot be wrong about a keyword, so only the schema has an opinion.
      # Those tools declare `additionalProperties: false` instead.
      #
      # Deliberately not memoized: this reads back whatever `perform` is
      # right now, and caching it means anything that redefines the method
      # leaves a stale answer behind for the life of the process. It is a
      # method lookup against an LLM round trip.
      def accepted_keywords
        params = method(:perform).parameters
        return :any if params.any? { |kind, _| kind == :keyrest }

        params.filter_map { |kind, key| key if [:key, :keyreq].include?(kind) } - [:context]
      end

      # Audience asks "may this person do it"; scope asks "may this
      # credential". They are different questions and both have to pass —
      # an admin using a read-only MCP token is still an admin, and the
      # token still may not write.
      def enforce_scope!(context)
        required = Scopes.for_tool(self)
        return if Scopes.satisfied?(context.scopes, required)

        raise Errors::Forbidden,
              "This credential is not allowed to do that. It would need the #{required} scope."
      end

      def enforce_audience!(context)
        case audience
        when :user  then context.user!
        when :admin then context.admin!
        end
      end

      # Tools answer in JSON. `structured_content` is what a well-behaved
      # MCP client reads; the text block carries the same payload, because
      # clients (and the Messages API tool loop) that ignore
      # structuredContent still have to get the data.
      def ok(data)
        MCP::Tool::Response.new(
          [{ type: "text", text: JSON.pretty_generate(data) }],
          structured_content: data
        )
      end

      # `extra` carries structured detail a model needs to act on rather
      # than parse out of prose — today the confirmation token and the
      # sentence to read aloud. It lands in `structuredContent`, so a
      # client can render the question itself instead of trusting the
      # model to quote it.
      def error(message, code: "error", **extra)
        payload = { error: code, message: message }.merge(extra.compact)
        MCP::Tool::Response.new(
          [{ type: "text", text: JSON.pretty_generate(payload) }],
          error: true,
          structured_content: payload
        )
      end

      # List tools cap their own page size. A model that asks for 5,000
      # rows is not malicious, it just has no idea what the table looks
      # like — and the resulting wall of JSON is context it cannot afford.
      def clamp_limit(value, default:, max:)
        return default if value.nil?

        limit = Integer(value, exception: false)
        raise Errors::InvalidArgument, "limit must be a number." if limit.nil?

        limit.clamp(1, max)
      end

      def clamp_offset(value)
        return 0 if value.nil?

        offset = Integer(value, exception: false)
        raise Errors::InvalidArgument, "offset must be a number." if offset.nil?

        offset.clamp(0, MAX_OFFSET)
      end

      # See `Tools::Untrusted` for why menu text is fenced. Kept here as a
      # one-word call because every tool that emits extracted text uses it
      # and the shorter name is the one that actually gets reached for.
      def untrusted(text) = Untrusted.fence(text)
    end
  end
end
