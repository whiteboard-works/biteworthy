class Admin::IngredientsController < AdminController
  before_action :set_ingredient, only: [:show, :edit, :update, :destroy, :add_tag, :remove_tag]
  respond_to :html

  def index
    @ingredients = Ingredient.all.includes(:tags, :varieties)
    # respond_with(@ingredients)
    respond_to do |format|
      format.html
      format.json { render json: IngredientDatatable.new(params, view_context: view_context) }
    end
  end

  def show
    respond_with(@ingredient)
  end

  def new
    @ingredient = Ingredient.new
    if params[:food_id]
      @food = Food.find(params[:food_id])
      @restaurant = Restaurant.find(@food.restaurant)
    end
    respond_with(@ingredient)
  end

  def edit
    # session[:return_to] ||= request.referer
  end

  def create
    @ingredient = Ingredient.find_or_create_by(name: ingredient_params[:name].singularize.downcase)
    @ingredient.update(ingredient_params)
    @ingredient.update(user: current_user)
    if params[:ingredient][:food_id]
      @food = Food.find(params[:ingredient][:food_id])
      @ingredient.foods << @food
      @ingredient.save
      redirect_to restaurant_food_path(@food.restaurant, @food), notice: "Ingredient created"
    else
      redirect_to admin_ingredients_path, notice: "Ingredient created"
    end
  end

  def update
    if @ingredient.update(ingredient_params)
      redirect_to admin_ingredients_path, notice: "Updated: #{@ingredient.name}"
    else
      redirect_to edit_admin_ingredients_path, notice: "Ingredient not updated"
    end
  end

  def destroy
    @ingredient.destroy
    redirect_to admin_ingredients_path
  end

  def add_tag
    if !params[:tag_id].empty?
      tag = Tag.find_by(name: params[:tag_id])
      @ingredient.tags << tag unless @ingredient.tags.include? tag
    end
    redirect_to edit_admin_ingredient_path(@ingredient)
  end

  def remove_tag
    tag = Tag.find_by(name: params[:tag_id])
    @ingredient.tags.destroy(tag)
    redirect_to edit_admin_ingredient_path(@ingredient)
  end

  private
  def set_ingredient
    if params[:id]
      @ingredient = Ingredient.find_by(name: params[:id])
    elsif params[:ingredient_id]
      @ingredient = Ingredient.find_by(name: params[:ingredient_id])
    end
    @tags      = Tag.where(variety: 'ingredient')
    @varieties = Variety.where(ingredient: @ingredient)
  end

  def ingredient_params
    params.require(:ingredient).permit(:name, :user_id)
  end
end
