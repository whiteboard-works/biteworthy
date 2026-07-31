require "swagger_helper"

def admin_menu_schema
  {
    type: :object,
    required: %w[id name],
    properties: {
      id:          { type: :string, format: :uuid },
      name:        { type: :string },
      description: { type: :string, nullable: true },
      position:    { type: :integer },
      sections: {
        type: :array,
        items: {
          type: :object,
          properties: {
            id:          { type: :string, format: :uuid },
            name:        { type: :string },
            description: { type: :string, nullable: true },
            position:    { type: :integer },
            items_count: { type: :integer }
          }
        }
      }
    }
  }
end

def admin_place_schema
  {
    type: :object,
    required: %w[restaurant_id hours],
    properties: {
      restaurant_id: { type: :string, format: :uuid },
      address: {
        type: :object, nullable: true,
        properties: {
          id:          { type: :string, format: :uuid },
          street:      { type: :string, nullable: true },
          city:        { type: :string, nullable: true },
          region:      { type: :string, nullable: true },
          postal_code: { type: :string, nullable: true },
          country:     { type: :string, nullable: true },
          latitude:    { type: :number, nullable: true },
          longitude:   { type: :number, nullable: true },
          map_provider_place_id: { type: :string, nullable: true }
        }
      },
      hours: {
        type: :array,
        items: {
          type: :object,
          properties: {
            id:          { type: :string, format: :uuid },
            day_of_week: { type: :integer },
            opens_at:    { type: :string, nullable: true, description: "HH:MM; null = closed" },
            closes_at:   { type: :string, nullable: true }
          }
        }
      }
    }
  }
end

RSpec.describe "admin/structure", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/admin/restaurants/{restaurant_id}/menus" do
    parameter name: :restaurant_id, in: :path, type: :string, format: :uuid

    get("List a restaurant's menus with their sections") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "menus → sections tree") do
        schema type: :object,
               required: %w[menus],
               properties: { menus: { type: :array, items: admin_menu_schema } }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:restaurant_id) do
          restaurant = create(:restaurant, :published)
          create(:menu_section, menu: create(:menu, restaurant: restaurant))
          restaurant.id
        end
        run_test!
      end
    end

    post("Create a menu") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          name:        { type: :string },
          description: { type: :string, nullable: true },
          position:    { type: :integer }
        }
      }

      response(201, "the created menu") do
        schema admin_menu_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:restaurant_id) { create(:restaurant, :published).id }
        let(:body) { { name: "Dinner", position: 1 } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/menus/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    patch("Rename or reposition a menu") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          name:        { type: :string },
          description: { type: :string, nullable: true },
          position:    { type: :integer }
        }
      }

      response(200, "the updated menu") do
        schema admin_menu_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:menu).id }
        let(:body) { { name: "Renamed" } }
        run_test!
      end
    end

    delete("Delete a menu (its sections go too; items are unsectioned, never deleted)") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(204, "deleted") do
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:menu).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/menus/{menu_id}/menu_sections" do
    parameter name: :menu_id, in: :path, type: :string, format: :uuid

    post("Create a section within a menu") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[name],
        properties: {
          name:        { type: :string },
          description: { type: :string, nullable: true },
          position:    { type: :integer }
        }
      }

      response(201, "the created section") do
        schema type: :object,
               required: %w[id menu_id name],
               properties: {
                 id:          { type: :string, format: :uuid },
                 menu_id:     { type: :string, format: :uuid },
                 name:        { type: :string },
                 description: { type: :string, nullable: true },
                 position:    { type: :integer },
                 items_count: { type: :integer }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:menu_id) { create(:menu).id }
        let(:body)    { { name: "Tacos" } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/menu_sections/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    delete("Delete a section — its items survive, unsectioned") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "deleted, with the count of items left unsectioned") do
        schema type: :object,
               required: %w[deleted items_unsectioned],
               properties: {
                 deleted:           { type: :boolean },
                 items_unsectioned: { type: :integer }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:menu_section).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/restaurants/{id}/place" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    get("Address + opening hours") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "the restaurant's place data") do
        schema admin_place_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:restaurant, :published).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/restaurants/{id}/address" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    put("Create or replace the address") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          street:      { type: :string },
          city:        { type: :string },
          region:      { type: :string },
          postal_code: { type: :string },
          country:     { type: :string },
          latitude:    { type: :number },
          longitude:   { type: :number },
          map_provider_place_id: { type: :string }
        }
      }

      response(200, "place data after the write") do
        schema admin_place_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:restaurant, :published).id }
        let(:body) { { street: "123 Main St", city: "Durango" } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/restaurants/{id}/hours" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    put("Replace the whole week's hours") do
      tags "Admin"
      description "Wholesale replacement — send every open day. Omitting opens_at/" \
                  "closes_at marks that day closed. A day may repeat for a SPLIT " \
                  "SHIFT (lunch 11:00-14:00, dinner 17:00-21:00); what it may not do " \
                  "is mix a closed row with a timed one (422 closed_day_has_hours). " \
                  "A partial write would advertise the wrong hours, so there is no " \
                  "per-day endpoint."
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[hours],
        properties: {
          hours: {
            type: :array,
            items: {
              type: :object,
              required: %w[day_of_week],
              properties: {
                day_of_week: { type: :integer, description: "0 (Sunday) – 6" },
                opens_at:    { type: :string, nullable: true, description: "HH:MM" },
                closes_at:   { type: :string, nullable: true }
              }
            }
          }
        }
      }

      response(200, "place data after the write") do
        schema admin_place_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:restaurant, :published).id }
        let(:body) { { hours: [{ day_of_week: 1, opens_at: "11:00", closes_at: "21:00" }] } }
        run_test!
      end

      response(422, "hours_must_be_an_array, hour_rows_must_be_objects, invalid_day_of_week, invalid_time_of_day, or closed_day_has_hours") do
        schema type: :object,
               properties: {
                 error:  { type: :string },
                 values: { type: :array, items: { type: :string } }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:restaurant, :published).id }
        let(:body) { { hours: [{ day_of_week: 9 }] } }
        run_test!
      end
    end
  end
end
