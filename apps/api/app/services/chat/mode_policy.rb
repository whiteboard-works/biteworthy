# frozen_string_literal: true

module Chat
  # How much the user has agreed to in advance, resolved per tool call.
  #
  # Four modes, one question each: may this call run now, does a human
  # have to see it first, or is it not allowed at all this turn.
  #
  #   planning      only reads run. Every write is refused, and the model
  #                 is told to describe what it would do instead.
  #   manual        the historical behaviour, and still the default: a
  #                 call parks whenever the tool says it needs a human.
  #   accept_edits  a standing yes to the edits, still a stop for the
  #                 calls no later edit can undo — see
  #                 `Tools::Base.unrecoverable_when`.
  #   auto          nothing parks.
  #
  # **The tool catalogue is identical in all four.** Hiding the write
  # tools in planning mode would read as the tidier design and is the one
  # thing that must not happen: tools render ahead of system in the cached
  # prefix, so a tool array that changes with the mode throws away the
  # whole ~21.6k-token cache on every switch. Refusing at call time costs
  # one wasted round instead, and leaves the transcript honest about what
  # the model tried.
  #
  # Modes are a chat concept. An MCP client has no mode and reaches
  # `Tools::Base#confirmation_gate` directly, which is why nothing here
  # loosens a check that lives down there — `auto` and `accept_edits`
  # skip the *parking*, and the tool boundary still sees a real grant.
  class ModePolicy
    PLANNING     = "planning"
    MANUAL       = "manual"
    ACCEPT_EDITS = "accept_edits"
    AUTO         = "auto"

    MODES   = [ PLANNING, MANUAL, ACCEPT_EDITS, AUTO ].freeze
    DEFAULT = MANUAL

    # What the model is told when it is holding tools it cannot use.
    # Phrased as a standing instruction rather than an error, because it
    # arrives as a `tool_result` and the model's next move should be to
    # write the plan, not to retry the call.
    REFUSAL = "Planning mode is on, so this write did not run and nothing changed. " \
              "Do not try it or any other write again this turn. Finish reading whatever " \
              "you still need, then describe the changes you would make and ask the user " \
              "to switch out of planning mode to run them."

    # Unknown modes resolve to `manual` rather than raising. The value
    # arrives from a client and rides in a jsonb payload that may have
    # been written by an older deploy; the safe reading of a value we do
    # not recognise is the strictest one that still works.
    def self.resolve(mode)
      value = mode.to_s
      MODES.include?(value) ? value : DEFAULT
    end

    attr_reader :mode

    def initialize(mode, skip_confirmations: false)
      @mode               = self.class.resolve(mode)
      @skip_confirmations = skip_confirmations
    end

    def planning? = mode == PLANNING

    # :run, :park, or :refuse for one call.
    #
    # `tool` is nil when the model invented a name. That is a bad call in
    # every mode, but only planning has to decide something about it: an
    # unknown tool cannot prove it only reads, so it does not get to run
    # here. The other modes hand it to `execute`, which answers with the
    # not-found error the model can act on.
    def decide(tool, args = {})
      return read_only?(tool) ? :run : :refuse if planning?
      return :run if mode == AUTO || @skip_confirmations
      return accept_edits(tool, args) if mode == ACCEPT_EDITS

      ToolCatalog.confirm_required?(tool, args) ? :park : :run
    end

    # Fails closed on a tool that declares no annotations at all, and on
    # one this build has never heard of: silence is not a claim that
    # nothing is written.
    #
    # Public because two callers need the same answer and must not drift
    # on it — planning mode deciding whether a call may run at all, and
    # `Conversation#mutated_since_last_user_message?` deciding whether
    # there is anything to offer to undo.
    def self.read_only?(tool)
      tool&.annotations_value&.read_only_hint == true
    end

    private

    # The standing yes, and the two things it does not cover.
    #
    # Undeclared destructive tools park. That is the whole safety
    # property: this mode is a grant someone gave in advance, and it
    # cannot extend to a call nobody has classified — including one added
    # to the codebase months after the grant was designed.
    def accept_edits(tool, args)
      return :park if tool.nil?
      return :park if tool.unrecoverable?(args)
      return :park if destructive?(tool) && !tool.recoverability_declared?

      :run
    end

    def read_only?(tool) = self.class.read_only?(tool)

    def destructive?(tool)
      tool.annotations_value&.destructive_hint == true
    end
  end
end
