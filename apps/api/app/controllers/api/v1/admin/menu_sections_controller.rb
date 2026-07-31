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
          attrs = section_params
          return if performed?

          section = menu.menu_sections.create!(attrs)
          render json: serialize_section(section), status: :created
        end

        def update
          section = MenuSection.find(params[:id])
          attrs = section_params
          return if performed?

          section.update!(attrs)
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
          StructureParams.parse(params, self)
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
