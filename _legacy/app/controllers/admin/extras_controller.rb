class Admin::ExtrasController < AdminController
  before_action :set_extra, only: [:show, :edit, :update, :destroy]
  before_action :just_set_extra, only: [:add_foods, :add_new_food, :remove_food, :add_new_price, :remove_photo]

  respond_to :html

  def index
    @extras = Extra.where(restaurant: @restaurant).order(:addon_type).page(@page).per(per_page_count)
    @restaurants = Restaurant.all
    respond_with(@extras)
  end

  def show
    respond_with(@extra)
  end

  def new
    @extra = Extra.new
    respond_with(@extra)
  end

  def edit
  end

  def create
    set_extrable
    @extra = Extra.new(extra_params)
    if @extra.save
      redirect_to admin_restaurant_extras_path(@restaurant), notice: "Extra: created"
    else
      render :new
    end

  end

  def update
    if @extra.update(extra_params)
      if params[:image]
        params[:image].each do |image|
          @extra.photos.new(user_id: current_user.id, photo_type: "Extra", image: image).save
        end
      end
      redirect_to edit_admin_restaurant_extra_path(@restaurant, @extra), notice: "Extra updated"
    else
      render :edit
    end
  end

  def destroy
    @extra.destroy
    redirect_to admin_restaurant_extras_path(@restaurant), notice: "Extra removed"
  end

  def remove_photo
    photo = Photo.find(params[:photo_id])
    @extra.photos.destroy(photo)
    redirect_to edit_admin_restaurant_extra_path(@restaurant, @extra)
  end

  private
  def just_set_extra
    if params[:id].present?
      @extra = Extra.find(params[:id])
    elsif params[:extra_id].present?
      @extra = Extra.find(params[:extra_id])
    end
  end

  def set_extra
    just_set_extra
    if @extra
      @restaurant = @extra.restaurant
      @foods = Food.where(restaurant: @restaurant)
      @extra_foods = Food.joins(:extras).where(restaurant: @restaurant)
      @tags        = Tag.order_variety_then_name
    end
  end

  def set_extrable
    keys = params[:extra].keys.select{|x| x.match(/extrable_*/) && x != "extrable_id"}
    keys.each do |key|
      if params[:extra][key].present?
        params[:extra][:extrable_id] = params[:extra][key].split(":").last
        params[:extra][:extrable_type] = params[:extra][key].split(":").first
      end
    end
  end

  def extra_params
    params.require(:extra).permit(:restaurant_id, :extrable_id, :extrable_type, :addon_type)
  end
end
