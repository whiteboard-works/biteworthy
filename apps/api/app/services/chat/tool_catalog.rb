# frozen_string_literal: true

module Chat
  # Bridges the MCP tool classes into Messages API tool definitions.
  #
  # Same registry, same audience filter, same descriptions — the whole
  # point of the tool layer is that the chat and an MCP client cannot
  # diverge on what a tool means or who may call it.
  #
  # **Most tools are declared but not loaded.** Forty-four schemas measured
  # 21,650 cached tokens carried on every turn of every conversation, and a
  # given turn uses two or three of them. The core domains stay resident
  # because they open nearly every conversation; the rest are marked
  # `defer_loading` and pulled in on demand by the server-side tool-search
  # tool.
  #
  # Deferral is specifically what preserves prompt caching. Tool search
  # *appends* the schemas it finds rather than swapping the tool array, so
  # the cached prefix survives — which is why this beats choosing a bundle
  # ourselves per turn: tools render ahead of system in that prefix, so
  # changing the array throws the whole cache away.
  module ToolCatalog
    # The domains that open conversations. Discovery answers "what can I
    # eat", profile answers "what do I avoid", and meta is the map the
    # model reads when the route is not obvious — deferring that one would
    # hide the index to everything else.
    CORE_DOMAINS = %i[meta discovery profile].freeze

    # Regex over BM25: the names here are deliberate, structured, and
    # domain-prefixed (`edit_menu_structure`, `list_moderation_queue`), so
    # a pattern match is predictable in a way relevance scoring is not.
    SEARCH_TOOL = {
      type: "tool_search_tool_regex_20251119",
      name: "tool_search_tool_regex"
    }.freeze

    class << self
      def definitions(context)
        resident, deferred = Tools::Registry.for(context).partition { |tool| core?(tool) }

        # The API rejects a request where every tool is deferred, and the
        # search tool itself must never be. Core tools are :public or
        # :user, so even a signed-out caller has some — but assert it
        # rather than trust it, because the failure mode is a 400 on every
        # turn rather than a degraded answer.
        raise "chat would ship an all-deferred tool set" if resident.empty?

        [SEARCH_TOOL] +
          resident.map { |tool| definition(tool) } +
          deferred.map { |tool| definition(tool, deferred: true) }
      end

      # A tool a client must confirm before it runs. The tool decides —
      # from `destructive_hint`, or from `confirm_when` against the actual
      # arguments — so the gate follows the tool rather than a list here
      # that would drift out of date.
      #
      # Arguments matter because some calls are dangerous only in one
      # direction: adding an avoid is safe, removing one is not.
      def confirm_required?(tool, args = {})
        tool&.requires_confirmation?(args) == true
      end

      def core?(tool)
        CORE_DOMAINS.include?(Tools::Registry.domain_of(tool))
      end

      private

      def definition(tool, deferred: false)
        payload = {
          name:         tool.name_value,
          description:  tool.description_value,
          input_schema: tool.input_schema_value.to_h
        }
        deferred ? payload.merge(defer_loading: true) : payload
      end
    end
  end
end
