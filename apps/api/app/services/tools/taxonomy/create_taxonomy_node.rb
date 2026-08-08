# frozen_string_literal: true

module Tools
  module Taxonomy
    class CreateTaxonomyNode < Taxonomy::Base
      tool_name "create_taxonomy_node"
      title "Add an ingredient or tag to the taxonomy"
      description <<~TEXT
        Add a node to the ingredient tree or the tag tree. Search with
        `search_taxonomy` first — a duplicate under a slightly different slug
        splits every dish that references it, and `aliases` exist so
        "garbanzo" can resolve to the existing "chickpea" instead.

        `path` places the node in the tree, lowest-to-highest dotted, e.g.
        `dairy.cheese.cheddar`. The parent must already exist. The path is how
        allergen tags get derived — anything under `dairy.` produces
        "contains-dairy" — so putting a node in the wrong branch produces
        wrong allergen data for every dish that uses it.

        `slug` and `path` can never be changed afterwards. Get them right now:
        renaming a slug drops the joins that resolve by it, and moving a path
        orphans everything beneath it.
      TEXT

      input_schema(
        properties: {
          kind: KIND_PROPERTY,
          slug: { type: "string", description: "Permanent identifier, e.g. 'dairy-cheddar'." },
          name: { type: "string", description: "Human name, e.g. 'Cheddar'." },
          path: { type: "string", description: "Dotted ltree path, e.g. 'dairy.cheese.cheddar'. Parent must exist." },
          aliases: {
            type: "array", items: { type: "string" },
            description: "Ingredients only. Other names menus use for this, e.g. ['garbanzo']."
          },
          allergen: { type: "boolean", description: "Ingredients only. Whether this is itself an allergen." },
          family: {
            type: "string",
            description: "Tags only, and permanent. Which kind of label this is.",
            enum: Tag::FAMILIES
          },
          description: { type: "string", description: "Tags only. What the label means." }
        },
        required: %w[kind slug name path]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      def self.perform(context:, kind:, slug:, name:, path:, **extra)
        context.admin!
        model = model_for(kind)
        validate_path!(kind, path)

        if model.exists?(slug: slug)
          raise Errors::InvalidArgument, "A #{kind} with slug '#{slug}' already exists."
        end

        node = model.create!(attrs_for(kind, slug, name, path, extra))
        ok(created: true, node: node_row(node, kind))
      end

      def self.attrs_for(kind, slug, name, path, extra)
        base = { slug: slug, name: name, path: path }
        if kind == "ingredient"
          base.merge(
            aliases:  Array(extra[:aliases]).map(&:to_s).reject(&:blank?),
            allergen: extra[:allergen] == true
          )
        else
          family = extra[:family].to_s
          unless Tag::FAMILIES.include?(family)
            raise Errors::InvalidArgument, "Tags need a family: #{Tag::FAMILIES.join(', ')}."
          end

          base.merge(family: family, description: extra[:description].presence)
        end
      end
      private_class_method :attrs_for
    end
  end
end
