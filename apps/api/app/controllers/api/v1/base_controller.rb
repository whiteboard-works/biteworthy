module Api
  module V1
    class BaseController < ApplicationController
      respond_to :json

      before_action :authenticate_user!

      rescue_from ActiveRecord::RecordNotFound,    with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid,     with: :render_unprocessable
      rescue_from ActionController::ParameterMissing, with: :render_unprocessable

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

      # Shared pagination parsing for the index actions. Each controller
      # passes its own bounds (they differ per resource); the offset cap
      # is uniform across the API.
      def page_limit(default:, max:)
        (params[:limit].presence || default).to_i.clamp(1, max)
      end

      def page_offset
        (params[:offset].presence || 0).to_i.clamp(0, MAX_OFFSET)
      end
    end
  end
end
