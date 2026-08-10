# frozen_string_literal: true

module Menus
  # The filtered menu for one restaurant.
  #
  # The filter runs in Ruby and NEVER removes rows: an item the caller
  # can't eat comes back with `status: "hidden"` and a populated
  # `reasons[]`. That is the honest-disclosure contract — a hidden item
  # must always be able to say why — so it has to survive the query.
  #
  # Ranking is separate. With taste signals the response is re-sorted by
  # `taste_score`; otherwise the order is `popularity DESC, name ASC`.
  # Score never hides anything; it only reorders and highlights.
  #
  # Callers: Api::V1::ItemsController and Tools::Discovery::GetMenu.
  class Query
    # `user` is the signed-in caller (nil when anonymous) and only drives
    # the per-user extras — taste scores, "never hide" overrides, and the
    # saved flag. It does not build the filter; pass that in.
    def initialize(restaurant:, filter:, user: nil, public_host: nil)
      @restaurant  = restaurant
      @filter      = filter
      @user        = user
      @public_host = public_host
    end

    def call
      items = load_items
      {
        restaurant_id: @restaurant.id,
        filter:        @filter.summary,
        items:         serialize_all(items)
      }
    end

    # Single-item payload for the dish detail route. No taste scoring —
    # the detail page never reorders, so paying for the scoring query
    # would buy nothing.
    def serialize_one(item)
      serialize(
        item,
        labels:        Labels.for_filter([item], @filter),
        override_ids:  override_item_ids([item]),
        review_counts: review_counts_for([item])
      )
    end

    private

    def load_items
      @restaurant.items.published
                 .includes(menu_section: :menu, photo_attachment: :blob)
                 .order(popularity: :desc, name: :asc)
                 .to_a
    end

    def serialize_all(items)
      labels        = Labels.for_filter(items, @filter)
      override_ids  = override_item_ids(items)
      review_counts = review_counts_for(items)

      signals      = @filter.taste_signals_for(@user)
      scores       = signals&.any? ? TasteScoring.scores_for(restaurant_id: @restaurant.id, signals: signals) : nil
      taste_labels = Labels.for_taste(scores)

      rendered = items.map do |item|
        serialize(item, labels: labels, override_ids: override_ids, review_counts: review_counts,
                        scores: scores, taste_labels: taste_labels)
      end

      rendered.sort_by! { |i| [-(i[:taste_score] || 0.0), -i[:popularity], i[:name]] } if scores
      rendered
    end

    # Keep these keys stable — mobile + web bind to them via generated TS
    # types, and docs/openapi.json should match.
    def serialize(item, labels:, override_ids: Set.new, review_counts: {}, scores: nil, taste_labels: nil)
      reasons   = @filter.reasons_for(item, labels)
      section   = item.menu_section
      score_row = scores&.fetch(item.id, nil)

      {
        id:                 item.id,
        restaurant_id:      item.restaurant_id,
        name:               item.name,
        description:        item.description,
        confidence:         item.confidence,
        popularity:         item.popularity,
        ingredient_ids:     item.denormalized_ingredient_ids,
        tag_ids:            item.denormalized_tag_ids,
        menu_section_id:    section&.id,
        menu_section_name:  section&.name,
        status:             reasons.empty? ? "visible" : "hidden",
        reasons:            reasons,
        overridden_by_user: override_ids.include?(item.id),
        reviews_count:      review_counts.fetch(item.id, 0),
        photo_url:          photo_url_for(item),
        # null / [] whenever the caller has no taste signals.
        taste_score:        score_row&.fetch(:score),
        taste_reasons:      taste_reasons_for(score_row, taste_labels),
        human_verified:     item.human_verified?,
        human_verified_at:  item.human_verified_at,
        restaurant_verified: item.restaurant_verified?,
        restaurant_verified_at: item.restaurant_verified_at
      }
    end

    # Tags first, then ingredients, both in the SQL's sorted-uuid order,
    # so the reason chips render in a stable sequence across requests.
    def taste_reasons_for(score_row, taste_labels)
      return [] if score_row.nil?

      labels = taste_labels || Labels::EMPTY
      score_row[:matched_liked_tag_ids].map do |tag_id|
        { kind: "liked_tag", tag_id: tag_id, tag_name: labels[:tags][tag_id]&.dig(:name) }
      end +
        score_row[:matched_liked_ingredient_ids].map do |ing_id|
          { kind: "liked_ingredient", ingredient_id: ing_id,
            ingredient_name: labels[:ingredients][ing_id]&.dig(:name) }
        end
    end

    # One grouped query so the restaurant page can badge "X reviews" per
    # item without an N+1. Counts only `.visible` reviews — hidden ones
    # must not inflate the public number.
    def review_counts_for(items)
      ids = items.map(&:id)
      return {} if ids.empty?
      Review.visible.where(item_id: ids).group(:item_id).count
    end

    # The caller's "never hide" overrides. Empty Set when anonymous, so
    # `overridden_by_user` stays accurate rather than absent.
    def override_item_ids(items)
      return Set.new unless @user
      ids = items.map(&:id)
      return Set.new if ids.empty?

      Set.new(UserItemOverride.where(user_id: @user.id, item_id: ids, never_hide: true).pluck(:item_id))
    end

    def photo_url_for(item)
      return nil unless @public_host
      return nil unless item.photo.attached?

      Rails.application.routes.url_helpers.rails_blob_url(item.photo, host: @public_host)
    end
  end
end
