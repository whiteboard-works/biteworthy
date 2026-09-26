# frozen_string_literal: true

module Menus
  # Taste signals inferred from what a signed-in user actually DID —
  # favorited a dish, or rated one — rather than what they typed into
  # the taste quiz. `Filter#taste_signals_for` folds these in underneath
  # the explicit profile so Top Picks can show before anyone has
  # onboarded.
  #
  # A favorited dish's tags/ingredients count as liked; a dish rated
  # >= LIKED_RATING_MIN counts as liked, one rated <= DISLIKED_RATING_MAX
  # counts as disliked. Bounded to the most recent *_LIMIT rows of each —
  # two queries total, independent of how many dishes are on the menu
  # being requested (see items_query_budget_spec).
  class ImplicitTasteSignals
    FAVORITES_LIMIT      = 50
    REVIEWS_LIMIT        = 50
    LIKED_RATING_MIN     = 4
    DISLIKED_RATING_MAX  = 2

    Signals = Struct.new(
      :liked_ingredient_ids, :liked_tag_ids,
      :disliked_ingredient_ids, :disliked_tag_ids,
      keyword_init: true
    )

    class << self
      def for_user(user)
        favorited_tag_ids, favorited_ingredient_ids = favorite_arrays_for(user)
        rated_liked_tags, rated_liked_ingredients,
          rated_disliked_tags, rated_disliked_ingredients = review_arrays_for(user)

        liked_tags           = (favorited_tag_ids + rated_liked_tags).uniq
        liked_ingredients    = (favorited_ingredient_ids + rated_liked_ingredients).uniq
        disliked_tags        = rated_disliked_tags.uniq
        disliked_ingredients = rated_disliked_ingredients.uniq

        # A tag/ingredient the user's own activity calls both ways (e.g.
        # favorited one spicy dish but rated a different spicy dish a 1)
        # is not a signal either direction — cancel it rather than guess.
        Signals.new(
          liked_tag_ids:           liked_tags           - disliked_tags,
          liked_ingredient_ids:    liked_ingredients    - disliked_ingredients,
          disliked_tag_ids:        disliked_tags        - liked_tags,
          disliked_ingredient_ids: disliked_ingredients - liked_ingredients
        )
      end

      private

      # One query, capped, reading the denormalized arrays straight off
      # `items` via the join — never `item.tag_ids`/`item.ingredient_ids`
      # on a loaded record, which would shadow the column with the
      # has_many-through reader and cost a query per favorite.
      def favorite_arrays_for(user)
        rows = FavoriteItem.joins(:item)
                            .where(user_id: user.id)
                            .order(created_at: :desc)
                            .limit(FAVORITES_LIMIT)
                            .pluck("items.tag_ids", "items.ingredient_ids")

        [ rows.flat_map { |tag_ids, _| tag_ids }, rows.flat_map { |_, ingredient_ids| ingredient_ids } ]
      end

      # One query, capped. Only the reviewer's own visible reviews —
      # a hidden (moderated) review shouldn't feed anyone's picks,
      # including its author's.
      def review_arrays_for(user)
        rows = Review.visible
                     .joins(:item)
                     .where(user_id: user.id)
                     .order(created_at: :desc)
                     .limit(REVIEWS_LIMIT)
                     .pluck(:rating, "items.tag_ids", "items.ingredient_ids")

        liked_tags = []
        liked_ingredients = []
        disliked_tags = []
        disliked_ingredients = []

        rows.each do |rating, tag_ids, ingredient_ids|
          if rating >= LIKED_RATING_MIN
            liked_tags.concat(tag_ids)
            liked_ingredients.concat(ingredient_ids)
          elsif rating <= DISLIKED_RATING_MAX
            disliked_tags.concat(tag_ids)
            disliked_ingredients.concat(ingredient_ids)
          end
        end

        [ liked_tags, liked_ingredients, disliked_tags, disliked_ingredients ]
      end
    end
  end
end
