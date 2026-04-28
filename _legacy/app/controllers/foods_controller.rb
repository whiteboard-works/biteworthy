class FoodsController < ApplicationController
  before_action :set_food, only: [:show]

  respond_to :html

  def index
    @restaurant = Restaurant.find(params[:restaurant_id])
    @foods = Food.where(restaurant: @restaurant)
    respond_with(@foods)
  end

  def show
    @ingredients = Ingredient.joins(:foods).where('foods.id in (?)', @food.id)
    respond_with(@food)
  end

  private
    def set_food
      @food = Food.find(params[:id])
      @restaurant = Restaurant.find(@food.restaurant_id)
    end
end
