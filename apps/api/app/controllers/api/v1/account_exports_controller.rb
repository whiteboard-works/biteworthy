module Api
  module V1
    # GET /api/v1/account/export — legal remediation E3.
    #
    # Returns the caller's personal data as a single JSON archive,
    # backing the Privacy Policy "Access / export your data" right.
    # Authenticated only — a user can export only their own data.
    #
    # Scope: the personal records tied to the account (profile, reviews,
    # suggestions, visit history). It intentionally does NOT dump the
    # shared menu graph (restaurants, items, taxonomy) — that's public
    # data, not the user's personal data.
    class AccountExportsController < BaseController
      def show
        user = current_user
        render json: {
          exported_at:       Time.current.iso8601,
          account:           account_section(user),
          profile:           profile_section(user.profile),
          reviews:           user.reviews.order(:created_at).map { |r| review_section(r) },
          suggestions:       user.suggestions.order(:created_at).map { |s| suggestion_section(s) },
          restaurant_visits: user.restaurant_visits.newest_first.map { |v| visit_section(v) }
        }
      end

      private

      def account_section(user)
        {
          id:           user.id,
          email:        user.email,
          handle:       user.handle,
          display_name: user.display_name,
          provider:     user.provider,
          created_at:   user.created_at.iso8601
        }
      end

      def profile_section(profile)
        return nil if profile.nil?
        {
          avoid_ingredient_ids:    profile.avoid_ingredient_ids,
          avoid_tag_ids:           profile.avoid_tag_ids,
          prefer_tag_ids:          profile.prefer_tag_ids,
          liked_ingredient_ids:    profile.liked_ingredient_ids,
          liked_tag_ids:           profile.liked_tag_ids,
          disliked_ingredient_ids: profile.disliked_ingredient_ids,
          disliked_tag_ids:        profile.disliked_tag_ids,
          strictness:              profile.strictness,
          primary_dietary_profile_slug: profile.primary_dietary_profile&.slug
        }
      end

      def review_section(review)
        {
          id:         review.id,
          item_id:    review.item_id,
          rating:     review.rating,
          body:       review.body,
          hidden:     review.hidden?,
          created_at: review.created_at.iso8601
        }
      end

      def suggestion_section(suggestion)
        {
          id:           suggestion.id,
          kind:         suggestion.kind,
          subject_type: suggestion.subject_type,
          subject_id:   suggestion.subject_id,
          payload:      suggestion.payload,
          status:       suggestion.status,
          created_at:   suggestion.created_at.iso8601
        }
      end

      def visit_section(visit)
        {
          id:                  visit.id,
          restaurant_id:       visit.restaurant_id,
          viewed_on:           visit.viewed_on,
          items_visible_count: visit.items_visible_count,
          items_hidden_count:  visit.items_hidden_count
        }
      end
    end
  end
end
