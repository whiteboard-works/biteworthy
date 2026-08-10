# frozen_string_literal: true

module Tools
  module Taxonomy
    class DeleteTaxonomyNode < Taxonomy::Base
      tool_name "delete_taxonomy_node"
      title "Delete an unused ingredient or tag"
      description <<~TEXT
        Remove a taxonomy node. Only works when nothing references it — no
        child nodes, no dishes, no dietary presets, no add-ons, and nobody's
        saved avoid list. If anything does, the call is refused and the counts
        come back so you can say what is in the way.

        That refusal is the safety property. A node sitting in someone's avoid
        list would vanish from their filter silently, weakening what they set
        up to protect themselves, because profiles tolerate ids that no longer
        resolve.

        This is for cleaning up a typo'd node created minutes ago. Merging a
        duplicate into a real node is not supported yet — say so rather than
        deleting one side.
      TEXT

      input_schema(
        properties: {
          kind: KIND_PROPERTY,
          slug: { type: "string", description: "Which node to delete." }
        },
        required: %w[kind slug]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      # The node is shared taxonomy — recreating one by the same slug does
      # not restore what pointed at it.
      unrecoverable_when { true }

      def self.perform(context:, kind:, slug:)
        context.admin!
        node = find_node!(kind, slug)

        ::Taxonomy::Writer.destroy!(node)
        ok(deleted: true, kind: kind, slug: slug)
      rescue ::Taxonomy::Writer::InUse => e
        # Not an error the model should apologise for — it asked a fair
        # question and the answer is "these things are in the way".
        ok(deleted: false, reason: "in_use", references: e.references.select { |_, n| n.positive? })
      end
    end
  end
end
