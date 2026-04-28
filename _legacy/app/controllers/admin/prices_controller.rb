class Admin::PricesController < AdminController
  before_action :set_price, only: [:show, :edit, :update, :destroy, :add_new_price]
  before_action :find_priced, only: [:show, :edit, :update, :destroy]
  respond_to :html

  def index
    @prices = Price.all
    respond_with(@prices)
  end

  def show
    respond_with(@price)
  end

  def new
    @price = Price.new
    respond_with(@price)
  end

  def edit
  end

  def create
    @price = @priced.prices.new(price_params)
    redirect_to edit_polymorphic_path([:admin, @priced.restaurant, @priced])
  end

  def update
    if @price.update(price_params)
      if @price.priced_type == "Item"
        redirect_to edit_admin_restaurant_item_path(@priced.restaurant, @priced), notice: "Price/Size updated"
      else
        redirect_to edit_polymorphic_path([:admin, @priced.restaurant, @priced]), notice: "Price/Size updated"
      end
    else
      render :edit
    end
  end

  def destroy
    @price_id = @price.id
    @price.destroy
    respond_to do |format|
       format.html { redirect_to :back }
       format.json { head :no_content }
       format.js   { render layout: false }
     end
  end

  def add_new_price
    price = Price.find_or_create_by(price_params)
    if price.errors.present?
      @notice = price.errors.full_messages.to_sentence
    end
    @object = @priced
    respond_to do |format|
       format.html { redirect_to edit_polymorphic_path([:admin, @priced.restaurant, @priced]) }
       format.json { head :no_content }
       format.js   { render "admin/prices/add_new" }
     end
  end

  private
  def set_price
    @price = Price.find(params[:id]) if params[:id].present?
    if params[:price].present? && price_params[:priced_id].present? && price_params[:priced_type].present?
      @priced = price_params[:priced_type].constantize.find(price_params[:priced_id])
    end
  end

  def price_params
    params.require(:price).permit(:priced_type, :priced_id, :value, :size)
  end

  def find_priced
    if params.include?(:priced_type) && params.include?(:priced_id)
      @priced = params[:priced_type].classify.constantize.find(params[:priced_id])
    else
       params.each do |name, value|
          if name =~ /(.+)_id$/
            puts "name=#{name}, value=#{value}"
             @priced = $1.classify.constantize.find(value)
          end
       end
     end
     if !@priced && @price
       @priced = @price.priced_type.classify.constantize.find(@price.review_id)
     end
     @priced
  end
end
