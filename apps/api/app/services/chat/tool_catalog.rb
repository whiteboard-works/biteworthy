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

      # A tool a client must confirm before it runs. `destructive_hint`
      # is the tool's own declaration, so the gate follows the tool
      # rather than a list here that would drift out of date.
      def confirm_required?(tool)
        tool&.annotations_value&.destructive_hint == true
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
