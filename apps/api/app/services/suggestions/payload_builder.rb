# frozen_string_literal: true

# Validates a proposed correction and returns the jsonb payload a
# `Suggestion` stores.
#
# Both doors reach this: `Tools::Suggestions::SuggestCorrection` and
# `Api::V1::SuggestionsController#create`. They take different arguments —
# the tool takes a flat `slug`, REST takes a nested `payload` hash whose
# key depends on the kind — so what is shared is the *rule*, not the
# parameters. Each door adapts its own input and renders its own error.
#
# The rule that matters: an unknown slug is rejected at submit time, not
# at accept time. `SuggestionResolver` raises on a bad slug when the owner
# tries to apply it, which surfaces the submitter's typo to the wrong
# person days later — and by then the submitter is gone. The tool has
# enforced this since M3a; the REST endpoint took `params[:payload]`
# straight to `to_unsafe_h` and queued whatever arrived.
#
# Root-scoped (`::Suggestions::PayloadBuilder`) when called from inside
# `Tools::`, for the same reason `::Places::Writer` and
# `::Admin::ItemEditor` are — a bare `Suggestions::` there resolves to
# `Tools::Suggestions::`.
module Suggestions
  class PayloadBuilder
    class InvalidPayload < StandardError; end

    # Separate so a caller can say something more useful than the generic
    # message: the tool appends "Use search_taxonomy", which is advice
    # only a model can act on.
    class UnknownSlug < InvalidPayload; end

    KINDS = SuggestionResolver::ITEM_KINDS

    class << self
      # Returns the payload hash with STRING keys — that is what the
      # jsonb column already holds for every historical row, and what
      # `SuggestionResolver#apply!` reads back.
      def call(kind:, slug: nil, name: nil)
        raise InvalidPayload, "kind must be one of: #{KINDS.join(', ')}." unless KINDS.include?(kind)

        case kind
        when "rename"
          { "name" => required_name(name) }
        when "add_ingredient", "remove_ingredient"
          { "ingredient_slug" => existing_slug(Ingredient, slug, "ingredient") }
        when "add_tag", "remove_tag"
          { "tag_slug" => existing_slug(Tag, slug, "tag") }
        else
          # KINDS is SuggestionResolver::ITEM_KINDS, edited by someone who
          # may never open this file. Without this branch a sixth kind
          # passes the guard above, falls through to nil, and hits a
          # NOT NULL column — a 500 on both doors, for adding a constant.
          raise InvalidPayload, "kind '#{kind}' has no payload rule here yet."
        end
      end

      # The slug REST nests under a kind-dependent key. Kept here so the
      # controller does not have to know which key goes with which kind —
      # that mapping is the same fact as the one `call` encodes.
      def slug_from(payload)
        payload["ingredient_slug"] || payload["tag_slug"]
      end

      private

      def required_name(name)
        value = name.to_s.strip
        raise InvalidPayload, "kind 'rename' needs a name." if value.empty?

        value
      end

      def existing_slug(model, slug, label)
        value = slug.to_s.strip
        raise InvalidPayload, "That kind needs an #{label} slug." if value.empty?
        raise UnknownSlug, "No #{label} with slug '#{value}'." unless model.exists?(slug: value)

        value
      end
    end
  end
end
