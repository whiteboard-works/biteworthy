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
    # **A nil tool is not a call, and no mode has a decision to make
    # about it.** It is nil when the model invented or misspelled a name,
    # or named one outside this caller's audience — and `execute` answers
    # all three with a not-found (plus a spelling suggestion) having run
    # nothing. There is no grant to withhold and nothing to authorize, so
    # every mode hands it straight through.
    #
    # Deciding on it instead meant answering the model's *typo* with the
    # mode's reason, which is a reason it believes. Planning told a
    # misspelled `get_menu` that "this write did not run" and to stop
    # attempting writes for the rest of the turn — a read, refused as a
    # write, with the turn's remaining tool use talked out of it.
    # `accept_edits` parked, so the turn stopped and asked a person to
    # approve a tool that does not exist; `park` reads its sentence off
    # the tool, so the question arrived blank.
    def decide(tool, args = {})
      return :run if tool.nil?

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
    # Reached only with a real tool — `decide` returns on nil before it
    # gets here. The fail-closed rule below is about a tool that
    # *exists* and nobody has classified; that is the safety property,
    # and it is a different fact from a name that resolves to nothing.
    def accept_edits(tool, args)
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
