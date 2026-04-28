class Admin::ExtrasAjaxController < Admin::ExtrasController
  before_action :just_set_extra, only: [
    :add_tag, :add_food, :add_foods,
    :add_new_food, :add_new_tag,
    :remove_tag, :remove_tags, :remove_food,
    :tag_up]

  def add_new_tag
    tag = Tag.find_or_initialize_by(name: params[:tag][:name].downcase)
    tag.update(description: params[:tag][:description])
    @extra.tags << tag unless @extra.tags.include? tag
    render partial: "admin/tags/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def add_tag
    unless (params[:tag_id].empty?)
      tag = Tag.find(params[:tag_id])
      @extra.tags << tag unless @extra.tags.include? tag
    end
    render partial: "admin/tags/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def remove_tag
    tag = Tag.find(params[:tag_id])
    @extra.tags.destroy(tag)
    render partial: "admin/tags/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def remove_tags
    @extra.tags.clear
    render partial: "admin/tags/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def tag_up
    @extra.foods.each do |food|
      food.tags.each do |tag|
        @extra.tags << tag unless @extra.tags.include? tag
      end
    end
    render partial: "admin/tags/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def add_new_food
    food = Food.find_or_initialize_by(name: params[:food][:name], restaurant: @extra.restaurant)
    food.update(description: params[:food][:description])
    @extra.foods << food unless @extra.foods.include? food
    render partial: "admin/foods/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def add_food
    foods = Food.where(id: params[:food_ids])
    if foods.present?
      foods.each do |food|
        @extra.foods << food unless @extra.foods.include? food
      end
    end
    render partial: "admin/foods/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def add_foods
    foods = Food.where(id: params[:food_ids])
    if foods.present?
      foods.each do |food|
        @extra.foods << food unless @extra.foods.include? food
      end
    end
    render partial: "admin/foods/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def remove_food
    food = Food.find(params[:food_id])
    @extra.foods.destroy(food)
    render partial: "admin/foods/inner/list", locals: {restaurant: @extra.restaurant, object: @extra }
  end

  def add_tags
    tags  = Tag.where(id: params[:tag_ids].split(","))
    extras = Extra.where(id: params[:extra_ids].split(","))
    extras.each do |extra|
      tags.each do |tag|
        unless extra.tags.include? tag
          extra.tags << tag
        end
      end
    end
    render html: "Updated: #{extras.map(&:name).to_sentence} with tags: #{tags.map(&:name).to_sentence}"
  end

  def tag_params
    params.require(:tag).permit(:name, :description, :variety, :icon, :user_id)
  end
end
