include Rails.application.routes.url_helpers

class FoodDatatable < ApplicationDatatable
  def_delegators :@view, :link_to, :image_food

  def view_columns
    @view_columns ||= {
      restaurant:  { source: "Food.restaurant.name" },
      name:        { source: "Food.name", searchable: false },
      description: { source: "Food.description", orderable: false },
      actions:     { source: "Food.id", orderable: false, cond: :eq}
    }
  end

  def data
    restaurant = params[:restaurant_id]
    records.map do |record|
      {
        restaurant:  link_to(record.restaurant.name, restaurant_food_path(restaurant, record)),
        name:        record.name,
        description: record.description,
        actions:     link_to('<i class="far fa-edit"></i>'.html_safe, edit_admin_restaurant_food_path(restaurant, record), class: "action-icon") +
        link_to('<i class="far fa-trash"></i>'.html_safe, admin_restaurant_food_path(restaurant, record), class: "action-icon", method: :delete, data: { confirm: 'Are you sure?' })
      }
    end
  end

  private

  def get_raw_records
    Food.where(restaurant_id: params[:restaurant_id])
  end
end
