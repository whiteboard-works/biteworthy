class Admin::RestaurantsController < AdminController
  before_action :set_restaurant, only: [:show, :edit, :update, :destroy, :remove_photo]

  respond_to :html

  def index
    @restaurants = Restaurant.all.order(active: :desc).order(:name)
    respond_with(@restaurants)
  end

  def show
    @menus          = Menu.where(restaurant: @restaurant).order(:name)
    @menu_groups    = MenuGroup.where(restaurant: @restaurant).order(:name)
    @active_items   = Item.where(restaurant: @restaurant).active.order(:name)
    @inactive_items = Item.where(restaurant: @restaurant).inactive.order(:name)
    @foods          = Food.where(restaurant: @restaurant).order(:name)
    @additions      = Extra.where(restaurant: @restaurant, addon_type: Extra.addon_types[:addition])
    @choices        = Extra.where(restaurant: @restaurant, addon_type: Extra.addon_types[:choice])
  end

  def new
    @restaurant = Restaurant.new
    # @restaurant.addresses.build
  end

  def edit
  end

  def create
    @restaurant = Restaurant.new(restaurant_params)
    if @restaurant.save
      if params[:image]
        save_images(@restaurant, params[:image])
      end
      redirect_to admin_restaurants_path
    else
      redirect_to edit_admin_restaurants_path, alert: @restaurant.errors.full_messages
    end
  end

  def update
    if @restaurant.update(restaurant_params)
      if params[:image]
        save_images(@restaurant, params[:image])
      end
      redirect_to edit_admin_restaurant_path(@restaurant), notice: "Updated"
    else
      redirect_to edit_admin_restaurant_path(@restaurant), alert: @restaurant.errors.full_messages
    end

  end

  def destroy
    @restaurant.destroy
    redirect_to admin_restaurants_path
  end

  def remove_photo
    photo = Photo.find(params[:photo_id])
    @restaurant.photos.destroy(photo)
    redirect_to edit_admin_restaurant_path(@restaurant), notice: "Photo removed"
  end

  private
  def set_restaurant
    if params[:id]
      @restaurant = Restaurant.find(params[:id])
    elsif params[:restaurant_id]
      @restaurant = Restaurant.find(params[:restaurant_id])
    end
  end

    def create_address

    end

    def restaurant_params
      params.require(:restaurant).permit(:name, :slogan, :about, :disclaimer, :inside_seating, :outside_seating, :cash_only, :delivers, :active, :website,
        addresses_attributes: [:restaurant_id, :phone_number, :street, :city, :state, :zip, :latitude, :longitude, :place_id])
    end
end
