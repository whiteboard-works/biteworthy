# frozen_string_literal: true

module Tools
  module Suggestions
    class SuggestCorrection < Suggestions::Base
      audience :user

      tool_name "suggest_correction"
      title "Suggest a fix to a dish"
      description <<~TEXT
        Propose a correction to a published dish: add or remove an ingredient
        or tag, or rename it. This queues the change for the restaurant's
        owner or an admin — it does not edit the live menu.

        Use this when a user tells you our data is wrong ("that has no dairy",
        "they renamed it"). Resolve the ingredient or tag with
        `search_taxonomy` first; an unknown slug is rejected here rather than
        rotting in the queue.

        Removing an ingredient is the direction that can hurt someone — it
        un-hides the dish for people avoiding it. Only suggest a removal when
        the user is telling you about the dish itself, never to make a menu
        look better.
      TEXT

      KINDS = SuggestionResolver::ITEM_KINDS

      input_schema(
        properties: {
          item_id: { type: "string", description: "The dish's UUID." },
          kind:    { type: "string", description: "What kind of correction.", enum: KINDS },
          slug: {
            type: "string",
            description: "Ingredient or tag slug, for the add_/remove_ kinds. Must already exist."
          },
          name: { type: "string", description: "The corrected dish name, for kind 'rename'." }
        },
        required: %w[item_id kind]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      def self.perform(context:, item_id:, kind:, slug: nil, name: nil)
        user = context.user!
        raise Errors::InvalidArgument, "kind must be one of: #{KINDS.join(', ')}." unless KINDS.include?(kind)

        item    = Item.published.joins(:restaurant).merge(Restaurant.published).find(item_id)
        payload = build_payload(kind, slug, name)

        suggestion = Suggestion.create!(
          user: user, subject: item, kind: kind, status: "pending", payload: payload
        )
        ok(suggestion_row(suggestion))
      end

      # Validated here rather than at accept time: SuggestionResolver
      # raises on a bad slug when the owner tries to apply it, which
      # surfaces the submitter's typo to the wrong person days later.
      def self.build_payload(kind, slug, name)
        case kind
        when "rename"
          value = name.to_s.strip
          raise Errors::InvalidArgument, "kind 'rename' needs a name." if value.empty?
          { "name" => value }
        when "add_ingredient", "remove_ingredient"
          { "ingredient_slug" => resolve!(Ingredient, slug, "ingredient") }
        when "add_tag", "remove_tag"
          { "tag_slug" => resolve!(Tag, slug, "tag") }
        end
      end
      private_class_method :build_payload

      def self.resolve!(model, slug, label)
        value = slug.to_s.strip
        raise Errors::InvalidArgument, "That kind needs an #{label} slug." if value.empty?
        unless model.exists?(slug: value)
          raise Errors::InvalidArgument, "No #{label} with slug '#{value}'. Use search_taxonomy."
        end

        value
      end
      private_class_method :resolve!
    end
  end
end
