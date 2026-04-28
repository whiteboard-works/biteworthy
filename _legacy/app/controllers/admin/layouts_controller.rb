class Admin::LayoutsController < AdminController

  def home
    @active_restaurants = Restaurant.where(active: true).order(:name)
    @inactive_restaurants = Restaurant.where(active: false).order(:name)
  end
end
