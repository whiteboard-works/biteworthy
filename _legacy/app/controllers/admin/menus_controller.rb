class Admin::MenusController < AdminController
  before_action :set_menu_on_id, only: [:show, :edit, :update, :destroy]

  respond_to :html

  def all
    @menus = Menu.all.order(:name)
  end

  def index
    @menus = Menu.where(restaurant_id: @restaurant)
      .includes(:menu_groups)
    respond_with(@menus)
  end

  def show
    respond_with(@menu)
  end

  def new
    @menu = Menu.new
    if params[:restaurant_id] && params[:restaurant_id]
      @restaurant = Restaurant.find(params[:restaurant_id])
    end
    respond_with(@menu)
  end

  def edit
    @menu_groups = MenuGroup.joins(:menus).where('menus.id = ?', @menu).where(restaurant: @menu.restaurant).order(:name)
  end

  def create
    @menu = Menu.new(menu_params)
    if @menu.save
      redirect_to admin_restaurant_menus_path(@menu.restaurant_id)
    else
      render :new
    end
  end

  def update
    if @menu.update(menu_params)
      redirect_to admin_restaurant_menus_path(@menu.restaurant_id)
    else
      render :edit
    end
  end

  def destroy
    @menu.destroy
    redirect_to admin_restaurant_menus_path(@restaurant), alert: "Menu Group Destroyed"
  end

  private
  def set_menu_on_id
    @menu = Menu.find(params[:id])
  end

  def set_menus
    @menus = Menu.where(restaurant: @restaurant).page(@page).per(per_page_count)
  end

  def menu_params
    params.require(:menu).permit(:id, :restaurant_id, :name, :description, seasons_attributes: [:name, :start_date, :end_date, :single_day], hours_attributes: [:opens, :closes, :day])
  end

end
