module Api
  module V1
    module Admin
      # Sub-menus within a menu ("Tacos", "Drinks").
      #
      #   POST         /api/v1/admin/menus/:menu_id/menu_sections
      #   PATCH/DELETE /api/v1/admin/menu_sections/:id
      #
      # Destroy nullifies its items (MenuSection has_many :items,
      # dependent: :nullify) — a reorganization must never delete
      # dishes, it just leaves them unsectioned.
      class MenuSectionsController < BaseController
        def create
          menu = Menu.find(params[:menu_id])
          section = menu.menu_sections.create!(section_params)
          render json: serialize_section(section), status: :created
        end

        def update
          section = MenuSection.find(params[:id])
          section.update!(section_params)
          render json: serialize_section(section)
        end

        def destroy
          section = MenuSection.find(params[:id])
          orphaned = section.items.count
          section.destroy!
          render json: { deleted: true, items_unsectioned: orphaned }
        end

        private

        def section_params
          attrs = {}
          attrs[:name]        = params[:name].to_s if params.key?(:name) && params[:name].is_a?(String)
          attrs[:description] = params[:description] if params.key?(:description) &&
                                                        (params[:description].nil? || params[:description].is_a?(String))
          attrs[:position]    = params[:position].to_i if params.key?(:position)
          attrs
        end

        def serialize_section(section)
          {
            id:          section.id,
            menu_id:     section.menu_id,
            name:        section.name,
            description: section.description,
            position:    section.position,
            items_count: section.items.count
          }
        end
      end
    end
  end
end
