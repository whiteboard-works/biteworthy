# frozen_string_literal: true

module Tools
  module Suggestions
    class SuggestCorrection < Suggestions::Base
      # Public, unlike the rest of this domain. Anonymous correction is a
      # deliberate product decision on the REST door — "Anonymous
      # suggestions land with user_id: nil but still queue for the owner"
      # — and the two doors answering differently is the drift this layer
      # exists to prevent. Suggesting a fix costs a reviewer's attention,
      # not data: nothing here touches a live menu, and `/mcp` has had a
      # 30/min anonymous ceiling since #550.
      audience :public

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

      # `context.user` rather than `user!` — an anonymous correction is
      # allowed and lands with `user_id: nil`, which `suggestion_row`
      # already compacts the submitter out of.
      def self.perform(context:, item_id:, kind:, slug: nil, name: nil)
        item    = Item.published.joins(:restaurant).merge(Restaurant.published).find(item_id)
        payload = ::Suggestions::PayloadBuilder.call(kind: kind, slug: slug, name: name)

        suggestion = Suggestion.create!(
          user: context.user, subject: item, kind: kind, status: "pending", payload: payload
        )
        ok(suggestion_row(suggestion))
      rescue ::Suggestions::PayloadBuilder::UnknownSlug => e
        # Only a model can act on this hint, so it is appended here rather
        # than baked into the shared rule a browser also hits.
        raise Errors::InvalidArgument, "#{e.message} Use search_taxonomy."
      rescue ::Suggestions::PayloadBuilder::InvalidPayload => e
        raise Errors::InvalidArgument, e.message
      end
    end
  end
end
