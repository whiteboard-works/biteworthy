class Admin::MenuGroupsController < AdminController
  before_action :set_menu_group_on_id, only: [:show, :edit, :update, :destroy]
  respond_to :html

  def all
    @menu_groups = MenuGroup.all.order(:name)
  end

  def index
    @menu_groups = MenuGroup.where(restaurant_id: @restaurant)
      .includes(:menus)
      .order('menus.name, menu_groups.name')
    respond_with(@menu_groups)
  end

  def show
    respond_with(@menu_group)
  end

  def new
    @menu_group = MenuGroup.new
    if params[:restaurant_id] && params[:restaurant_id]
      @restaurant = Restaurant.find(params[:restaurant_id])
    end
    respond_with(@menu_group)
  end

  def edit
    @items = Item.joins(:menu_groups).where("items_menu_groups.menu_group_id in (?)", @menu_group).where(restaurant: @menu_group.restaurant).order(:name)
  end

  def create
    @menu_group = MenuGroup.new(menu_group_params)
    if @menu_group.save
      redirect_to admin_restaurant_menu_groups_path(@menu_group.restaurant_id)
    else
      render :new
    end
  end

  def update
    if @menu_group.update(menu_group_params)
      redirect_to admin_restaurant_menu_groups_path(@menu_group.restaurant_id)
    else
      render :edit
    end
  end

  def destroy
    @menu_group.destroy
    redirect_to admin_restaurant_menu_groups_path(@restaurant), alert: "Menu Group Destroyed"
  end

  private
    def set_menu_group_on_id
      @menu_group = MenuGroup.find(params[:id])
    end

    def set_menu_groups
      @menu_groups = MenuGroup.where(restaurant: @restaurant).page(@page).per(per_page_count)
    end

    def menu_group_params
       params.require(:menu_group).permit(:id, :restaurant_id, :name, :description, :menu_order, menu_ids: [])
    end
end
