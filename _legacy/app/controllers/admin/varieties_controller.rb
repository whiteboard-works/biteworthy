class Admin::VarietiesController < AdminController
  before_action :set_variety, only: [:show, :edit, :update, :destroy]

  def index
    @ingredient = Ingredient.find_by(name: params[:ingredient_id])
    @varieties = Variety.where(ingredient: @ingredient).order('varieties.name')
  end

  def all
    @varieties = Variety.joins(:ingredient).includes(:ingredient).order('ingredients.name').order('varieties.name')
  end

  def show
    @foods = Food.joins(:ingredients).where('ingredients.id in (?)', @variety.ingredient).includes(:restaurant)
  end

  def new
    @variety = Variety.new
  end

  def edit
  end

  def create
    @variety = Variety.new(variety_params)

    respond_to do |format|
      if @variety.save
        format.html { redirect_to admin_ingredient_variety_path(@variety.ingredient, @variety), notice: 'Variety was successfully created.' }
        format.json { render :show, status: :created, location: admin_ingredient_variety_path(@variety.ingredient, @variety) }
      else
        format.html { render :new }
        format.json { render json: @variety.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @variety.update(variety_params)
        format.html { redirect_to admin_ingredient_variety_path(@variety.ingredient, @variety), notice: 'Variety was successfully updated.' }
        format.json { render :show, status: :ok, location: admin_ingredient_variety_path(@variety.ingredient, @variety) }
      else
        format.html { render :edit }
        format.json { render json: @variety.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @variety.destroy
    respond_to do |format|
      format.html { redirect_to admin_varieties_url, notice: 'Variety was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    def set_variety
      @variety = Variety.find(params[:id])
    end

    def variety_params
      params.require(:variety).permit(:name, :food_id, :ingredient_id, :ingredient_first)
    end
end
