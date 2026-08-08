# frozen_string_literal: true

module Chat
  # Bridges the MCP tool classes into Messages API tool definitions.
  #
  # Same registry, same audience filter, same descriptions — the whole
  # point of the tool layer is that the chat and an MCP client cannot
  # diverge on what a tool means or who may call it.
  module ToolCatalog
    class << self
      def definitions(context)
        Tools::Registry.for(context).map { |tool| definition(tool) }
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

      private

      def definition(tool)
        {
          name:         tool.name_value,
          description:  tool.description_value,
          input_schema: tool.input_schema_value.to_h
        }
      end
    end
  end
end
