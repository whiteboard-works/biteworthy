class Admin::AddressesController < AdminController
  before_action :set_address, only: [:show, :edit, :update, :destroy]

  respond_to :html

  def index
    @addresses = Address.all
  end

  def new
    @address = Address.new
  end

  def edit
  end

  def create
    @address = Address.new(address_params)
    if @address.save
      redirect_to edit_admin_restaurant_path(@restaurant)
    else
      redirect_to edit_admin_restaurant_address_path(@restaurant, @address), alert: @address.errors.full_messages
    end
  end

  def update
    if @address.update(address_params)
      redirect_to edit_admin_restaurant_path(@restaurant)
    else
      redirect_to edit_admin_restaurant_address_path(@restaurant, @address), alert: @address.errors.full_messages
    end
  end

  def destroy
    @address.destroy
    redirect_to edit_admin_restaurant_path(@restaurant)
  end

  private
    def set_address
      @address = Address.find(params[:id])
      @restaurant = Restaurant.find(@address.restaurant_id)
    end

    def address_params
      params.require(:address).permit(:phone_number, :street, :city, :state, :zip, :latitude, :longitude, :restuarant_id, :place_id)
    end

end
