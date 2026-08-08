# frozen_string_literal: true

module Tools
  module Taxonomy
    class EditTaxonomyNode < Taxonomy::Base
      tool_name "edit_taxonomy_node"
      title "Edit an ingredient or tag"
      description <<~TEXT
        Change a taxonomy node's display name, its aliases, its allergen flag,
        or a tag's description. Omitted fields are left alone.

        `aliases` is what lets a menu saying "garbanzo" resolve to "chickpea",
        so it is the highest-value field here. It REPLACES the list — send the
        full set, including the ones already there.

        `allergen` on an ingredient is not cosmetic: allergen tags are derived
        from the tree, so flipping it changes what gets hidden for people
        filtering on that allergen. Existing dishes are not re-derived by this
        call; a re-scan is what picks it up.

        `slug`, `path`, and a tag's `family` cannot be changed. If one is
        wrong, create the right node and migrate the references.
      TEXT

      input_schema(
        properties: {
          kind:     KIND_PROPERTY,
          slug:     { type: "string", description: "Which node to edit." },
          name:     { type: "string", description: "New display name." },
          aliases: {
            type: "array", items: { type: "string" },
            description: "Ingredients only. The FULL alias list after the edit."
          },
          allergen:    { type: "boolean", description: "Ingredients only." },
          description: { type: "string", description: "Tags only." }
        },
        required: %w[kind slug]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, kind:, slug:, **fields)
        context.admin!
        node  = find_node!(kind, slug)
        attrs = editable_attrs(kind, fields)
        raise Errors::InvalidArgument, "Pass at least one field to change." if attrs.empty?

        node.update!(attrs)
        ok(node_row(node, kind).merge(changed: attrs.keys))
      end

      def self.editable_attrs(kind, fields)
        attrs = {}
        attrs[:name] = fields[:name].to_s if fields.key?(:name)

        if kind == "ingredient"
          attrs[:aliases]  = Array(fields[:aliases]).map(&:to_s).reject(&:blank?) if fields.key?(:aliases)
          attrs[:allergen] = fields[:allergen] == true                           if fields.key?(:allergen)
        elsif fields.key?(:description)
          attrs[:description] = fields[:description].presence
        end

        attrs
      end
      private_class_method :editable_attrs
    end
  end
end
