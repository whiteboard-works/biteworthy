# frozen_string_literal: true

module Tools
  # The topology's workflows, offered as MCP prompts.
  #
  # A Claude Desktop or Claude Code user sees prompts as things they can
  # pick before typing anything — "Scan a menu into the database" is a
  # better starting point than a blank box and forty-four tools. We already
  # know those workflows: `Tools::Topology::WORKFLOWS` names each one, its
  # tool sequence, and the single thing about it that surprises people.
  #
  # **Generated from that constant, never restated.** A prompt that drifts
  # from the topology would be documentation that lies to a model at
  # runtime — the exact failure the topology spec was written to prevent.
  # Adding a workflow gets a prompt for free; editing one updates both.
  #
  # Filtered like everything else: a workflow is offered only to a caller
  # who can run every step — by audience and by the scopes their credential
  # holds — so `prompts/list` never suggests a route that dead-ends in
  # `forbidden`. Same rule `Registry.for` applies to tools and
  # `Topology.for` applies to the map, delegated rather than restated.
  module WorkflowPrompts
    class << self
      def all
        @all ||= Topology::WORKFLOWS.map { |workflow| build(workflow) }.freeze
      end

      # Deferred to `Topology.workflows_for` rather than re-deciding here.
      # This used to filter on audience alone, which was the same answer
      # while audience was the only thing that gated a tool; once a scoped
      # credential could clear the audience check and still be missing a
      # step's scope, the two rules disagreed and this one offered routes
      # that dead-end. One rule, in one place.
      def for(context)
        offered = Topology.workflows_for(context).map { |flow| slug_for(flow[:name]) }.to_set
        all.select { |prompt| offered.include?(prompt.slug) }
      end

      private

      # Slugged from the name so the wire identifier is stable and readable
      # — `scan_a_menu_into_the_database`, not an index.
      def slug_for(name)
        name.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
      end

      def build(workflow)
        flow = workflow
        Class.new(MCP::Prompt) do
          prompt_name slug_for_name = Tools::WorkflowPrompts.send(:slug_for, flow[:name])
          title flow[:name]
          description "#{flow[:note]} Tools, in order: #{flow[:steps].join(' → ')}."

          define_singleton_method(:workflow_audience) { flow[:audience] }
          define_singleton_method(:workflow_steps)    { flow[:steps] }
          define_singleton_method(:slug)              { slug_for_name }

          define_singleton_method(:template) do |_args, server_context: nil|
            MCP::Prompt::Result.new(
              description: flow[:name],
              messages: [
                MCP::Prompt::Message.new(
                  role: "user",
                  content: MCP::Content::Text.new(
                    <<~TEXT.strip
                      #{flow[:name]}.

                      The tools for this, in the order they usually go: #{flow[:steps].join(' → ')}.

                      #{flow[:note]}

                      Ask me for anything you need before starting.
                    TEXT
                  )
                )
              ]
            )
          end
        end
      end
    end
  end
end
