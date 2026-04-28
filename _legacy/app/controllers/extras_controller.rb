class ExtrasController < ApplicationController
  before_action :set_extra, only: [:show]

  respond_to :html

  def index
    @extras = Extra.where(restaurant: @restaurant).order(:name).page(@page).per(per_page_count)
    @restaurants = Restaurant.all
    respond_with(@extras)
  end

  def show
    respond_with(@extra)
  end

  private
  def just_set_extra
    if params[:id]
      @extra = Extra.find(params[:id])
    elsif params[:extra_id]
      @extra = Extra.find(params[:extra_id])
    end
  end

  def set_extra
    just_set_extra
    if @extra
      @restaurant = @extra.restaurant
      @foods = Food.where(restaurant: @restaurant).order(:name)
      @extra_foods = Food.joins(:extras).where(restaurant: @restaurant).order(:name)
    end
  end

end
