class Admin::ItemsAjaxController < Admin::ItemsController
  before_action :just_set_item, only: [
    :add_tag, :add_foods,
    :add_new_food, :add_new_tag,
    :remove_tag, :remove_tags, :remove_food,
    :tag_up]

  def add_new_tag
    tag = Tag.find_or_initialize_by(name: params[:tag][:name].downcase)
    tag.update(description: params[:tag][:description])
    @item.tags << tag unless @item.tags.include? tag
    render partial: "admin/tags/inner/list", locals: {restaurant: @item.restaurant, object: @item }
  end

  def add_tag
    unless (params[:tag_id].empty?)
      tags = Tag.find(params[:tag_id])
      tags.each do |tag|
        @item.tags << tag unless @item.tags.include? tag
      end
    end
    render partial: "admin/tags/inner/list", locals: {restaurant: @item.restaurant, object: @item }
  end

  def remove_tag
    tag = Tag.find(params[:tag_id])
    @item.tags.destroy(tag)
    render partial: "admin/tags/inner/list", locals: {restaurant: @item.restaurant, object: @item }
  end

  def remove_tags
    @item.tags.clear
    render partial: "admin/tags/inner/list", locals: {restaurant: @item.restaurant, object: @item }
  end

  def tag_up
    @item.foods.each do |food|
      food.tags.each do |tag|
        @item.tags << tag unless @item.tags.include? tag
      end
      food.ingredients.each do |ingredient|
        ingredient.tags.each do |tag|
          @item.tags << tag unless @item.tags.include? tag
        end
      end
    end
    @item.extras.each do |extra|
      extra.extrable.tags.each do |tag|
        @item.tags << tag unless @item.tags.include? tag
      end
    end
    @item.tags.each do |tag|
      if tag.parent
        tag.ancestors.each do |ancestor|
          @item.tags << ancestor unless @item.tags.include? ancestor
        end
      end
    end
    render partial: "admin/tags/inner/list", locals: {restaurant: @item.restaurant, object: @item }
  end

  def add_new_food
    food = Food.find_or_initialize_by(name: food_params[:name], restaurant: @item.restaurant)
    food.update(food_params)
    @item.foods << food unless @item.foods.include? food
    render partial: "admin/foods/inner/list", locals: {restaurant: @item.restaurant, object: @item }
  end

  def add_foods
    foods = Food.where(id: params[:food_ids])
    if foods.present?
      foods.each do |food|
        @item.foods << food unless @item.foods.include? food
      end
    end
    render partial: "admin/foods/inner/list", locals: {restaurant: @item.restaurant, object: @item }
  end

  def remove_food
    food = Food.find(params[:food_id])
    @item.foods.destroy(food)
    render partial: "admin/foods/inner/list", locals: {restaurant: @item.restaurant, object: @item }
  end

  def add_tags
    tags  = Tag.where(id: params[:tag_ids].split(","))
    items = Item.where(id: params[:item_ids].split(","))
    items.each do |item|
      tags.each do |tag|
        unless item.tags.include? tag
          item.tags << tag
        end
      end
    end
    render html: "Updated: #{items.map(&:name).to_sentence} with tags: #{tags.map(&:name).to_sentence}"
  end
end
