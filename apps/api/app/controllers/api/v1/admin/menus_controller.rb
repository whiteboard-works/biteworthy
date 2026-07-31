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
          # One grouped count for the page instead of a COUNT per section.
          section_ids = menus.flat_map { |m| m.menu_sections.map(&:id) }
          counts = Item.where(menu_section_id: section_ids).group(:menu_section_id).count
          render json: { menus: menus.map { |m| serialize_menu(m, counts) } }
        end

        def create
          restaurant = Restaurant.find(params[:restaurant_id])
          attrs = menu_params
          return if performed?

          menu = restaurant.menus.create!(attrs)
          render json: serialize_menu(menu), status: :created
        end

        def update
          menu = Menu.find(params[:id])
          attrs = menu_params
          return if performed?

          menu.update!(attrs)
          render json: serialize_menu(menu)
        end

        def destroy
          Menu.find(params[:id]).destroy!
          head :no_content
        end

        private

        # Validate before coercing: `"abc".to_i` is 0 and a non-String
        # name would otherwise be dropped behind a 201, losing the
        # caller's value silently.
        def menu_params
          StructureParams.parse(params, self)
        end

        def serialize_menu(menu, counts = {})
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
                items_count: counts[section.id] || 0
              }
            end
          }
        end
      end
    end
  end
end
