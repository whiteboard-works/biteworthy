module Api
  module V1
    class BaseController < ApplicationController
      respond_to :json

      before_action :authenticate_user!

      rescue_from ActiveRecord::RecordNotFound,    with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid,     with: :render_unprocessable
      rescue_from ActionController::ParameterMissing, with: :render_unprocessable
      # A unique index is a domain rule the database enforces, not a bug.
      # Two controllers learned that separately — the admin namespace
      # rescued it, FavoriteItemsController rescued it inline — and the
      # review path, which had no model-level uniqueness validation to
      # catch it first, 500'd on an ordinary second review. It belongs
      # here so the next one does not have to rediscover it.
      #
      # A validation should still catch the common case with a sentence
      # worth reading; this is the concurrent-race backstop, and the
      # message is deliberately generic because the alternative is
      # relaying PG's "duplicate key value violates unique constraint
      # index_reviews_on_user_id_and_item_id" to a browser.
      rescue_from ActiveRecord::RecordNotUnique,   with: :render_already_exists

      # Upper bound on pagination offset — deep pagination past this is
      # almost always a scraper, and an unbounded offset is a cheap DoS.
      MAX_OFFSET = 10_000

      private

      def render_not_found(error)
        render json: { error: error.message }, status: :not_found
      end

      def render_unprocessable(error)
        render json: { error: error.message }, status: :unprocessable_entity
      end

      # Reported, not just rendered. Most of what lands here is a race on
      # a rule the caller can see — two tabs, one review — and 422 is the
      # honest answer. But a unique-index violation is also how a real
      # bug looks (a slug collision on a create path, say), and those
      # used to surface as 500s that something was watching. Swallowing
      # them into a tidy 422 would make the bug quieter, not rarer.
      def render_already_exists(error)
        Rails.error.report(error, handled: true, context: { path: request.path })
        render json: { error: "That already exists." }, status: :unprocessable_entity
      end

      # Shared pagination parsing for the index actions. Each controller
      # passes its own bounds (they differ per resource); the offset cap
      # is uniform across the API.
      def page_limit(default:, max:)
        (params[:limit].presence || default).to_i.clamp(1, max)
      end

      def page_offset
        (params[:offset].presence || 0).to_i.clamp(0, MAX_OFFSET)
      end

      # The origin absolute URLs should resolve from. Production sets
      # PUBLIC_HOST (clients fetch from a different origin than the API);
      # dev / CI fall back to the incoming request's base URL.
      def public_host
        ENV["PUBLIC_HOST"].presence || request.base_url
      end

      # Signed ActiveStorage blob URL for a record's attached `photo`,
      # or nil when none is attached. Shared by the item / review / user
      # serializers — built via the route helpers directly so it doesn't
      # depend on Devise's URL helpers being mixed into the controller.
      def photo_url_for(record)
        return nil unless record.photo.attached?
        Rails.application.routes.url_helpers.rails_blob_url(record.photo, host: public_host)
      end
    end
  end
end
