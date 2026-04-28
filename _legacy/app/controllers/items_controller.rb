class ItemsController < ApplicationController
  before_action :set_items, only: [:show]

  respond_to :html

  def show
    if current_user
      @review = Review.where(user_id: current_user.id, review_type: "Item", review_id: @item.id).first
    end
  end

  private
  def set_items
    @item = Item
      .includes(:reviews, :prices, :photos, :foods)
      .find(params[:id])
    @item_extras_choice   = @item.extras.where(addon_type: Extra.addon_types[:choice])
    @item_extras_addition = @item.extras.where(addon_type: Extra.addon_types[:addition])
    @restaurant = Restaurant
      .includes(:addresses, :photos)
      .find(@item.restaurant_id)
  end
end
