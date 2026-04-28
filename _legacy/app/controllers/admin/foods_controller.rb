class Admin::FoodsController < AdminController
  before_action :set_restaurant, only: [:all, :index, :show, :edit, :update, :destroy, :add_ingredient, :add_ingredient_by_name, :remove_photo]
  before_action :set_food, only: [
    :show, :edit, :update, :destroy,
    :add_ingredient, :add_ingredient_by_name,
    :remove_ingredient, :remove_variety, :remove_photo
  ]
  before_action :set_foods, only: [:all, :index]
  respond_to :html


  def all
    unless @foods
      @foods = Food.page(@page).per(per_page_count)
    end
  end

  def index
    @foods = Food.where(restaurant: @restaurant).page(@page).per(per_page_count)
    respond_to do |format|
      format.html
      format.json { render json: FoodDatatable.new(params, view_context: view_context) }
    end
  end

  def show
    respond_with(@food)
  end

  def get_menu_groups_by_restaurant
    restaurant = Restaurant.find(params[:restaurant_id])
    menu_groups = MenuGroup.where(restaurant_id: params[:restaurant_id])
    render partial: 'admin/modules/menu_groups_select', locals: {menu_groups: menu_groups, restaurant: restaurant}
  end

  def new
    @food = Food.new
    if params[:food] && params[:food][:restaurant_id]
      @restaurant = Restaurant.find(food_params[:restaurant_id])
    elsif params.has_key? :restaurant_id
      @restaurant = Restaurant.find(params[:restaurant_id])
    end
    respond_with(@food)
  end

  def edit
    @tags = Tag.all.order(:name)
  end

  def create
    @food = Food.new(food_params)
    if @food.save
      if params[:image]
        save_images(@food, params[:image])
      end
      redirect_to admin_foods_path
    else
      redirect_to :back
    end
  end

  def update
    if @food.update(food_params)
      if params[:image]
        save_images(@food, params[:image])
      end
      redirect_to edit_admin_restaurant_food_path(@food.restaurant, @food)
    else
      redirect_to edit_admin_restaurant_food_path(@food.restaurant, @food)
    end
  end

  def destroy
    @food.destroy
    redirect_to admin_foods_path
  end

  def add_new_food
    food = Food.find_or_create_by(name: food_params[:name], description: food_params[:description], restaurant_id: food_params[:restaurant_id])
    food.update(user: current_user)
    if params[:extra_id].present?
      @extra = Extra.find(params[:extra_id])
      @extra.foods << food
      redirect_to edit_admin_restaurant_extra_path(@extra.restaurant, @extra)
    elsif params[:item_id].present?
      @item = Item.find(params[:item_id])
      @item.foods << food
      redirect_to edit_admin_restaurant_item_path(@item.restaurant, @item)
    else
      redirect_to :back
    end
  end

  def add_ingredient
    if params[:ingredient_id].present?
      ingredient = Ingredient.find(params[:ingredient_id])
      @food.ingredients << ingredient unless @food.ingredients.include? ingredient
      redirect_to edit_admin_restaurant_food_path(@restaurant, @food)
    else
      redirect_to edit_admin_restaurant_food_path(@restaurant, @food), notice: "No ingredient selected"
    end
  end

  def add_ingredient_by_name
    if params[:ingredient].present?
      ingredient = Ingredient.find_or_create_by(name: params[:ingredient][:name].singularize.downcase.strip)
      if ingredient.valid?
        ingredient.update(user: current_user)
        if params[:ingredient][:variety].present?
          variety = Variety.find_or_create_by(ingredient: ingredient, name: params[:ingredient][:variety].singularize.downcase.strip)
          @food.varieties << variety unless @food.varieties.include? variety
        end
        @food.ingredients << ingredient unless @food.ingredients.include? ingredient
      else
        flash[:notice] = "Not a valid ingredient: #{ingredient.errors.full_messages}."
      end
    end
    redirect_to edit_admin_restaurant_food_path(@restaurant, @food)
  end

  def add_tag
    unless (params[:tag_id].empty?)
      tag = Tag.find(params[:tag_id])
      @food.tags << tag unless @food.tags.include? tag
    end
    redirect_to edit_admin_restaurant_food_path(@food.restaurant, @food)
  end

  def add_new_tag
    tag = Tag.find_or_initialize_by(name: params[:tag][:name])
    tag.update(description: params[:tag][:description])
    tag.update(user: current_user)
    @food.tags << tag unless @food.tags.include? tag
    redirect_to edit_admin_restaurant_food_path(@food.restaurant, @food)
  end

  def remove_ingredient
    ingredient = Ingredient.find(params[:ingredient_id])
    @food.ingredients.destroy(ingredient)
    redirect_to edit_admin_restaurant_food_path(@food.restaurant, @food)
  end

  def remove_variety
    variety = Variety.find(params[:variety_id])
    @food.varieties.destroy(variety)
    redirect_to edit_admin_restaurant_food_path(@food.restaurant, @food), notice: "#{variety.display_name} removed from #{@food.name}"
  end

  def remove_photo
    photo = Photo.find(params[:photo_id])
    @food.photos.destroy(photo)
    redirect_to edit_admin_restaurant_food_path(@restaurant, @food)
  end

  private
  def set_food
    if params[:id]
      @food = Food.find(params[:id])
    elsif params[:food_id]
      @food = Food.find(params[:food_id])
    end
  end

  def set_foods
    if params.has_key?(:filter_restaurant_id) && !params[:filter_restaurant_id].empty?
      @foods = Food.where(restaurant_id: params[:filter_restaurant_id]).page(@page).per(per_page_count)
    else
      @foods = Food.page(@page).per(per_page_count)
    end
  end

  def food_params
    params.require(:food).permit(:restaurant_id, :name, :description, :food_group, :user_id)
  end
end
