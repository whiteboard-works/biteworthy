# frozen_string_literal: true

module Tools
  module Profile
    # Profiles are stored as UUID arrays; models reason in slugs. This
    # translates one way for every profile tool's response, so a tool
    # result can be fed straight back into `update_avoid_lists` without
    # the model having to hold UUIDs.
    #
    # Ids that no longer resolve are dropped silently — the same way
    # filtering and scoring already ignore stale ids.
    module Serializer
      class << self
        def call(profile)
          ingredients = Ingredient.where(
            id: profile.avoid_ingredient_ids + profile.liked_ingredient_ids + profile.disliked_ingredient_ids
          ).index_by { |i| i.id.to_s }

          tags = Tag.where(
            id: profile.avoid_tag_ids + profile.liked_tag_ids + profile.disliked_tag_ids
          ).index_by { |t| t.id.to_s }

          {
            strictness:           profile.strictness,
            primary_preset:       profile.primary_dietary_profile&.slug,
            avoid_ingredients:    slugs(profile.avoid_ingredient_ids, ingredients),
            avoid_tags:           slugs(profile.avoid_tag_ids, tags),
            liked_ingredients:    slugs(profile.liked_ingredient_ids, ingredients),
            liked_tags:           slugs(profile.liked_tag_ids, tags),
            disliked_ingredients: slugs(profile.disliked_ingredient_ids, ingredients),
            disliked_tags:        slugs(profile.disliked_tag_ids, tags)
          }
        end

        private

        def slugs(ids, lookup)
          ids.filter_map { |id| lookup[id.to_s]&.slug }
        end
      end
    end
  end
end
