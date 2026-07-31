module Api
  module V1
    module Admin
      # Shared name/description/position parsing for menus and their
      # sections. Validates before coercing — `"abc".to_i` is 0 and a
      # non-String name would otherwise vanish behind a 201, so the
      # caller hears about bad input instead of getting a success with
      # their value quietly dropped.
      #
      # Renders the 422 on the controller itself and returns {}; callers
      # check `performed?` before continuing.
      module StructureParams
        module_function

        def parse(params, controller)
          attrs = {}

          if params.key?(:name)
            unless params[:name].is_a?(String)
              return reject(controller, "invalid_name")
            end
            attrs[:name] = params[:name]
          end

          if params.key?(:description)
            value = params[:description]
            unless value.nil? || value.is_a?(String)
              return reject(controller, "invalid_description")
            end
            attrs[:description] = value
          end

          if params.key?(:position)
            position = Integer(params[:position], exception: false)
            return reject(controller, "invalid_position") if position.nil?
            attrs[:position] = position
          end

          attrs
        end

        def reject(controller, error)
          controller.render json: { error: error }, status: :unprocessable_entity
          {}
        end
      end
    end
  end
end
