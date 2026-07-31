module Api
  module V1
    module Admin
      # Menus and their sections — the structure an admin reorganizes
      # when a scan lands everything in one bucket.
      #
      #   GET/POST   /api/v1/admin/restaurants/:restaurant_id/menus
      #   PATCH/DELETE /api/v1/admin/menus/:id
      #
      # Destroying a menu cascades to its sections (has_many dependent:
      # :destroy), and each section nullifies its items rather than
      # deleting them — losing a section must never lose the dishes.
      class MenusController < BaseController
        def index
          restaurant = Restaurant.find(params[:restaurant_id])
          menus = restaurant.menus.order(:position, :name).includes(:menu_sections)
          render json: { menus: menus.map { |m| serialize_menu(m) } }
        end

        def create
          restaurant = Restaurant.find(params[:restaurant_id])
          menu = restaurant.menus.create!(menu_params)
          render json: serialize_menu(menu), status: :created
        end

        def update
          menu = Menu.find(params[:id])
          menu.update!(menu_params)
          render json: serialize_menu(menu)
        end

        def destroy
          Menu.find(params[:id]).destroy!
          head :no_content
        end

        private

        def menu_params
          attrs = {}
          attrs[:name]        = params[:name].to_s if params.key?(:name) && params[:name].is_a?(String)
          attrs[:description] = params[:description] if params.key?(:description) &&
                                                        (params[:description].nil? || params[:description].is_a?(String))
          attrs[:position]    = params[:position].to_i if params.key?(:position)
          attrs
        end

        def serialize_menu(menu)
          {
            id:          menu.id,
            name:        menu.name,
            description: menu.description,
            position:    menu.position,
            sections: menu.menu_sections.sort_by { |s| [s.position.to_i, s.name.to_s] }.map do |section|
              {
                id:          section.id,
                name:        section.name,
                description: section.description,
                position:    section.position,
                items_count: section.items.size
              }
            end
          }
        end
      end
    end
  end
end
