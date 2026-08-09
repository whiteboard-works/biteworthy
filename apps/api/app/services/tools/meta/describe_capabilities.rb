# frozen_string_literal: true

module Tools
  module Meta
    class DescribeCapabilities < Tools::Base
      audience :public

      tool_name "describe_capabilities"
      title "What Biteworthy can do, and in what order"
      description <<~TEXT
        A map of the tools grouped by domain, the workflows they compose into,
        and the conventions that apply across all of them.

        Call this first when a request is open-ended ("help me eat here", "fix
        this menu") and you are not sure which tools it takes, or when a
        multi-step task has more than one plausible route. Skip it for a
        single obvious call.

        Only what THIS caller can actually run is listed. If a workflow you
        expected is missing, the caller is not signed in, is not an admin, or
        is connected with a credential that was granted narrower access — say
        that rather than trying the tool and reporting an error.

        Pass `domain` to get one group instead of all of them.
      TEXT

      input_schema(
        properties: {
          domain: {
            type: "string",
            description: "Limit to one domain. Omit for the whole map.",
            enum: Registry::DOMAINS.keys.map(&:to_s)
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, domain: nil)
        map = Topology.for(context)
        return ok(map) if domain.nil?

        selected = map[:domains].find { |row| row[:name].to_s == domain }
        unless selected
          raise Errors::InvalidArgument,
                "No domain '#{domain}' available to you. Call without a domain to see what is."
        end

        ok(
          domain:      selected,
          workflows:   map[:workflows].select { |flow| flow[:steps].intersect?(selected[:tools]) },
          conventions: map[:conventions]
        )
      end
    end
  end
end
