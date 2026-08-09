# frozen_string_literal: true

module Tools
  module Taxonomy
    # Shared plumbing for the ingredient/tag taxonomy tools.
    #
    # Ingredients and tags are near-identical trees with different
    # metadata, so `kind` picks the model rather than doubling the tool
    # count — a model choosing between `create_ingredient` and
    # `create_tag` alongside four other near-twins misroutes.
    #
    # The write rules — path shape, parent-must-exist, slug/path/family
    # immutability, and what counts as a reference that blocks a delete —
    # live in ::Taxonomy::Writer (root-scoped, because a bare `Taxonomy::`
    # here resolves to Tools::Taxonomy), shared with the admin REST
    # controllers. What stays here is this door's half: resolving a slug,
    # phrasing the refusals for a model to act on, and the wire rows.
    class Base < Tools::AdminBase
      KINDS = %w[ingredient tag].freeze

      KIND_PROPERTY = {
        type: "string",
        description: "Which tree. Ingredients are things in food; tags are labels like 'contains-dairy' or 'vegan'.",
        enum: KINDS
      }.freeze

      class << self
        def model_for(kind)
          raise Errors::InvalidArgument, "kind must be one of: #{KINDS.join(', ')}." unless KINDS.include?(kind)

          kind == "ingredient" ? Ingredient : Tag
        end

        def find_node!(kind, slug)
          model_for(kind).find_by(slug: slug.to_s) ||
            raise(Errors::NotFound, "No #{kind} with slug '#{slug}'.")
        end

        # The writer's errors are facts about the taxonomy; a model needs
        # the next action, so each is re-phrased as one.
        def translate_errors
          yield
        rescue ::Taxonomy::Writer::InvalidPath
          raise Errors::InvalidArgument,
                "path must be lowercase dot-separated segments, e.g. 'dairy.cheese.cheddar'."
        rescue ::Taxonomy::Writer::ParentMissing => e
          raise Errors::InvalidArgument, "Create the parent '#{e.parent}' first."
        rescue ::Taxonomy::Writer::ImmutableField => e
          raise Errors::InvalidArgument,
                "#{e.fields.join(' and ')} cannot change. Create the right node and migrate the references."
        end

        def node_row(node, kind)
          row = {
            kind: kind,
            slug: node.slug,
            name: node.name,
            path: node.path.to_s
          }
          if kind == "ingredient"
            row.merge(aliases: node.aliases, allergen: node.allergen)
          else
            row.merge(family: node.family, description: node.description)
          end
        end
      end
    end
  end
end
