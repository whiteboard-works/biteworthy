class RestaurantsController < ApplicationController
  skip_before_action :set_page, :set_restaurants, :set_restaurants, :set_menu, :set_menus, :set_menu_groups, :set_menu_group, :set_items, :set_item
  before_action :set_restaurant_know_how, only: :show
  respond_to :html

  def index
    redirect_to root_path
  end

  def show
  end

  private
  def set_restaurant_know_how
    @restaurant = Restaurant.where(id: params[:id]).includes(:tags, :addresses).first
    # @menus      = Menu.includes(:menu_groups)
    #   .includes(menu_groups: [items: [:reviews, :prices, :photos]])
    #   .where(restaurant_id: @restaurant.id)
    #   .order("menu_groups.menu_order")
    #   .order("reviews.rating DESC")
    if !@restaurant.active?
      redirect_to root_path, notice: "Looks like you can't go there, we apologize for the inconvenience."
    end
    @items = Item.where(restaurant: @restaurant).includes(:menu_groups, :tags, :reviews, :photos).uniq.to_a
  end
end
