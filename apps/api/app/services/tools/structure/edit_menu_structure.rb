# frozen_string_literal: true

module Tools
  module Structure
    class EditMenuStructure < Tools::AdminBase
      tool_name "edit_menu_structure"
      title "Reorganize a restaurant's menus and sections"
      description <<~TEXT
        Create, rename, reposition, or delete a menu or one of its sections.
        One operation per call; `action` picks which.

        This is the tool for a scan that landed everything in one bucket.
        Read the current shape with `get_menu_structure` first — every id
        here comes from there.

        Deleting NEVER deletes dishes. Deleting a section leaves its dishes
        unsectioned; deleting a menu deletes its sections and leaves all of
        their dishes unsectioned. The response says how many were affected.
        Say that number back to the user before they accept the result.

        `position` orders items within their parent, lowest first.
      TEXT

      ACTIONS = %w[
        create_menu update_menu delete_menu
        create_section update_section delete_section
      ].freeze

      input_schema(
        properties: {
          action:      { type: "string", description: "Which change to make.", enum: ACTIONS },
          restaurant:  { type: "string", description: "Restaurant slug or UUID. Required for create_menu." },
          menu_id: {
            type: "string",
            description: "Target menu. Required for the *_menu actions and for create_section."
          },
          section_id: {
            type: "string",
            description: "Target section. Required for update_section and delete_section."
          },
          name:        { type: "string", description: "Name, for create and rename." },
          description: { type: "string", description: "Optional description." },
          position:    { type: "integer", description: "Sort order within the parent, lowest first." }
        },
        required: ["action"],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false)

      class << self
        def perform(context:, action:, **args)
          context.admin!
          unless ACTIONS.include?(action)
            raise Errors::InvalidArgument, "action must be one of: #{ACTIONS.join(', ')}."
          end

          send(:"perform_#{action}", **args)
        end

        private

        def perform_create_menu(restaurant: nil, **attrs)
          record = find_restaurant!(require_arg(restaurant, "restaurant"))
          menu   = record.menus.create!(structure_attrs(attrs, require_name: true))
          ok(created: "menu", menu: menu_row(menu))
        end

        def perform_update_menu(menu_id: nil, **attrs)
          menu  = Menu.find(require_arg(menu_id, "menu_id"))
          attrs = structure_attrs(attrs)
          raise Errors::InvalidArgument, "Pass a name, description, or position." if attrs.empty?

          menu.update!(attrs)
          ok(updated: "menu", menu: menu_row(menu))
        end

        # Sections cascade; their items only lose the link. Reporting the
        # count is the point — an admin tidying menus must not discover
        # afterwards that 40 dishes fell out of every section.
        def perform_delete_menu(menu_id: nil, **_)
          menu = Menu.find(require_arg(menu_id, "menu_id"))
          section_ids = menu.menu_sections.pluck(:id)
          unsectioned = Item.where(menu_section_id: section_ids).count
          menu.destroy!

          ok(deleted: "menu", sections_deleted: section_ids.size, items_unsectioned: unsectioned)
        end

        def perform_create_section(menu_id: nil, **attrs)
          menu    = Menu.find(require_arg(menu_id, "menu_id"))
          section = menu.menu_sections.create!(structure_attrs(attrs, require_name: true))
          ok(created: "section", section: section_row(section))
        end

        def perform_update_section(section_id: nil, **attrs)
          section = MenuSection.find(require_arg(section_id, "section_id"))
          attrs   = structure_attrs(attrs)
          raise Errors::InvalidArgument, "Pass a name, description, or position." if attrs.empty?

          section.update!(attrs)
          ok(updated: "section", section: section_row(section))
        end

        def perform_delete_section(section_id: nil, **_)
          section = MenuSection.find(require_arg(section_id, "section_id"))
          unsectioned = section.items.count
          section.destroy!

          ok(deleted: "section", items_unsectioned: unsectioned)
        end

        def require_arg(value, name)
          raise Errors::InvalidArgument, "That action needs #{name}." if value.blank?
          value
        end

        # Validate before coercing. `"abc".to_i` is 0, so a bad position
        # would silently sort a section to the top instead of erroring.
        def structure_attrs(args, require_name: false)
          attrs = {}
          attrs[:name] = args[:name].to_s if args.key?(:name)
          attrs[:description] = args[:description] if args.key?(:description)

          if args.key?(:position)
            position = Integer(args[:position], exception: false)
            raise Errors::InvalidArgument, "position must be a whole number." if position.nil?
            attrs[:position] = position
          end

          raise Errors::InvalidArgument, "name is required." if require_name && attrs[:name].blank?
          attrs
        end

        def menu_row(menu)
          { id: menu.id, name: menu.name, description: menu.description, position: menu.position }
        end

        def section_row(section)
          {
            id: section.id, menu_id: section.menu_id, name: section.name,
            description: section.description, position: section.position
          }
        end
      end
    end
  end
end
