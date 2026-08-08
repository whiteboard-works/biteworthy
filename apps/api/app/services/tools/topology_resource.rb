# frozen_string_literal: true

module Tools
  # The tool map as an MCP resource, so a client can read it without
  # spending a tool call and a turn on it.
  #
  # Same content as `describe_capabilities`; two surfaces because clients
  # differ — Claude Desktop reads resources, a bare Messages-API loop does
  # not. Both filter by the caller's audience.
  class TopologyResource < MCP::Resource
    URI = "biteworthy://topology"

    uri URI
    resource_name "topology"
    title "Biteworthy tool map"
    description "Which tools compose into which workflow, and the conventions that apply across all of them."
    mime_type "text/markdown"

    def self.contents(server_context: nil)
      MCP::Resource::TextContents.new(
        uri:       URI,
        mime_type: "text/markdown",
        text:      Topology.markdown(Context.new(server_context))
      )
    end
  end
end
