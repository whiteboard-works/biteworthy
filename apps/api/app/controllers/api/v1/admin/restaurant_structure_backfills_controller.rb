# frozen_string_literal: true

module Api
  module V1
    module Admin
      class RestaurantStructureBackfillsController < BaseController
        # POST /api/v1/admin/restaurants/:restaurant_id/backfill_structure
        def create
          restaurant = Restaurant.find(params[:restaurant_id])
          dry_run    = ActiveModel::Type::Boolean.new.cast(params[:dry_run])

          result = Restaurants::BackfillStructure.new(
            restaurant: restaurant,
            dry_run:    dry_run
          ).call

          render json: {
            restaurant_id:     restaurant.id,
            dry_run:           dry_run,
            sections_created:  result[:sections_created],
            variants_added:    result[:variants_added]
          }
        end
      end
    end
  end
end
