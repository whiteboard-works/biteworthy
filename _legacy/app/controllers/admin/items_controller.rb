class Admin::ItemsController < AdminController
  before_action :set_item, only: [:show, :edit, :update, :destroy]
  before_action :just_set_item, only: [
    :add_extra, :add_new,
    :add_new_price, :add_new_extra,
    :remove_menu_group, :remove_extra, :remove_photo
  ]

  respond_to :html


  def all
    unless @items
      @items = Item.page(@page).per(per_page_count)
    end
  end

  def add_tags
    # Uses ajax magic
  end

  def index
    @items = Item.where(restaurant_id: @restaurant).page(@page).per(per_page_count)
    respond_to do |format|
      format.html
      format.json { render json: ItemDatatable.new(params, view_context: view_context) }
    end
  end

  def restaurant_item_filter
  end

  def get_menu_groups_by_restaurant
     menu_groups = MenuGroup.where(restaurant_id: params[:restaurant_id])
     render partial: 'admin/modules/menu_groups_select', locals: {menu_groups: menu_groups, restaurant: @restaurant}
  end

  def new
    @item = Item.new
    @menu_group = MenuGroup.find(params[:menu_group_id]) if params[:menu_group_id]
    @menu_groups = MenuGroup.where(restaurant: @restaurant).order(:name)
    respond_with(@item)
  end

  def edit
  end

  def create
    @item = Item.new(item_params)
    if @item.save
      if params[:image]
        save_images(@item, params[:image])
      end
      redirect_to edit_admin_restaurant_item_path(@item.restaurant, @item)
    else
      render :new
    end
  end

  def update
    if @item.update(item_params)
      if params[:image]
        save_images(@item, params[:image])
      end
      flash[:notice] = "Item updated"
      redirect_to edit_admin_restaurant_item_path(@item.restaurant, @item)
    else
      flash[:notice] = "Item failed to update"
      render :edit
    end
  end

  def destroy
    @item.destroy
    redirect_to admin_restaurant_items_path(@restaurant)
  end

  def add_new
    # tag = Tag.find_or_initialize_by(name: params[:name], description: params[:description])
    # tag.update(tag_params)
    # @item.tags << tag unless @item.tags.include? tag
    # redirect_to edit_admin_restaurant_item_path(@item.restaurant, @item)
  end

  def add_new_price
    Price.create(priced_id: @item.id, priced_type: @item.class.to_s, value: params[:price][:value], size: params[:price][:size])
    respond_to do |format|
      format.html { redirect_to edit_admin_restaurant_item_path(@item.restaurant, @item), notice: 'Tag was successfully created.' }
      format.js { render "admin/prices/add_new" }
    end
  end

  def add_new_extra
    # From admin_extras_controller
    keys = params[:extra].keys.select{|x| x.match(/extrable_*/) && x != "extrable_id"}
    keys.each do |key|
      if params[:extra][key].present?
        params[:extra][:extrable_id] = params[:extra][key].split(":").last
        params[:extra][:extrable_type] = params[:extra][key].split(":").first
      end
    end

    if params[:extra][:extrable_id].present? && params[:extra][:extrable_type].present?
      extra = Extra.find_or_create_by(extrable_id: params[:extra][:extrable_id], extrable_type: params[:extra][:extrable_type], addon_type: Extra.addon_types[params[:addon_type]], restaurant: @item.restaurant)
      if extra && extra.valid?
        if @item.extras.select{ |e| e.extrable_id == extra.extrable_id && e.addon_type == extra.addon_type}.empty?
          @item.extras << extra
        else
          @notice = "#{@item.name} already has #{params[:addon_type]} of #{extra.extrable.name}"
        end
      elsif extra
        @notice = extra.errors.full_messages.to_sentence
      end
    else
      @notice = "No name provided for #{params[:addon_type]}"
    end
    respond_to do |format|
      format.html { redirect_to edit_admin_restaurant_item_path(@item.restaurant, @item), notice: @notice }
      format.js { render "admin/items/extras/new" }
    end
  end

  def add_extra
    if params[:extra_choice_id].present?
      extra = Extra.find(params[:extra_choice_id])
    elsif params[:extra_addition_id].present?
      extra ||= Extra.find(params[:extra_addition_id])
    else
      @notice = "No choice or addition selected"
    end

    if extra.present?
      if @item.extras.select{ |e| e.extrable_id == extra.extrable_id && e.addon_type == extra.addon_type}.empty?
        @item.extras << extra
      else
        @notice = "#{@item.name} already has #{extra.addon_type} of #{extra.extrable.name}"
      end
    end

    respond_to do |format|
      format.html { redirect_to edit_admin_restaurant_item_path(@item.restaurant, @item), notice: @notice }
      format.js { render "admin/items/extras/add" }
    end
  end

  def remove_menu_group
    menu_group = MenuGroup.find(params[:menu_group_id])
    @item.menu_groups.destroy(menu_group)
    redirect_to edit_admin_restaurant_item_path(@restaurant, @item), notice: "Menu Group removed"
  end

  def remove_extra
    extra = Extra.find(params[:extra_id])
    @extra = params[:extra_id]
    @item.extras.destroy(extra)
    respond_to do |format|
      format.html { redirect_to edit_admin_restaurant_item_path(@restaurant, @item), notice: "Extra removed" }
      format.js { }
    end

  end

  def remove_photo
    photo = Photo.find(params[:photo_id])
    @item.photos.destroy(photo)
    redirect_to edit_admin_restaurant_item_path(@restaurant, @item), notice: "Photo removed"
  end

  private
  def set_item
    just_set_item
    if @item.restaurant_id
      @restaurant  = Restaurant.find(@item.restaurant_id)
      @menu_groups = MenuGroup.includes(:restaurant).where(restaurant: @restaurant).order(:name)
      @foods       = Food.where(restaurant: @restaurant).order(:name)
      @extras      = Extra.where(restaurant: @restaurant).order(:name)
      @tags        = Tag.order_variety_then_name
    else
      @menu_groups = MenuGroup.includes(:restaurant).all.order('restaurants.name').order(:name)
    end
  end

  def just_set_item
    if params[:id]
      @item = Item.find(params[:id])
    elsif params[:item_id]
      @item = Item.find(params[:item_id])
    end
  end

  def item_params
    params.require(:item).permit(:restaurant_id, :name, :description, :status, :recommended, :user_id, menu_group_ids: [])
  end

  def food_params
    params.require(:food).permit(:name, :description)
  end

  def tag_params
    params.require(:tag).permit(:name, :description, :icon)
  end
end
