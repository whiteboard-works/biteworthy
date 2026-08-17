require "swagger_helper"

def admin_restaurant_row_schema
  {
    type: :object,
    required: %w[id slug name status archived_at],
    properties: {
      id:     { type: :string, format: :uuid },
      slug:   { type: :string },
      name:   { type: :string },
      status: { type: :string, enum: %w[draft published closed] },
      # Present on every row and null on most. `status` is untouched by
      # archiving, so a client that branches on status alone cannot tell
      # a live restaurant from a hidden one — this is the field that can.
      archived_at: { type: :string, format: "date-time", nullable: true },
      city: {
        type: :object, nullable: true,
        properties: { id: { type: :string, format: :uuid }, name: { type: :string } }
      },
      created_by_user_id: { type: :string, format: :uuid, nullable: true },
      claimed_by_user_id: { type: :string, format: :uuid, nullable: true },
      created_at:            { type: :string, format: "date-time" },
      items_count:           { type: :integer },
      suggested_items_count: { type: :integer },
      about:      { type: :string, nullable: true },
      website:    { type: :string, nullable: true },
      phone:      { type: :string, nullable: true },
      claimed_at: { type: :string, format: "date-time", nullable: true },
      items_by_confidence: { type: :object, additionalProperties: { type: :integer } }
    }
  }
end

def admin_item_row_schema
  {
    type: :object,
    required: %w[id restaurant_id name status confidence],
    properties: {
      id:               { type: :string, format: :uuid },
      restaurant_id:    { type: :string, format: :uuid },
      menu_section_id:  { type: :string, format: :uuid, nullable: true },
      name:             { type: :string },
      description:      { type: :string, nullable: true },
      status:           { type: :string, enum: %w[draft published removed] },
      confidence:       { type: :string, enum: %w[confirmed suggested inferred] },
      position:         { type: :integer },
      ingredient_count: { type: :integer },
      tag_count:        { type: :integer },
      ingredients: {
        type: :array,
        items: {
          type: :object,
          properties: {
            id:   { type: :string, format: :uuid },
            slug: { type: :string },
            name: { type: :string }
          }
        }
      },
      tags: {
        type: :array,
        items: {
          type: :object,
          properties: {
            id:     { type: :string, format: :uuid },
            slug:   { type: :string },
            name:   { type: :string },
            family: { type: :string }
          }
        }
      },
      modifiers: {
        type: :array,
        items: {
          type: :object,
          properties: {
            id:          { type: :string, format: :uuid },
            name:        { type: :string },
            kind:        { type: :string, enum: %w[choice addition side] },
            price_cents: { type: :integer, nullable: true }
          }
        }
      },
      variants: {
        type: :array,
        items: {
          type: :object,
          properties: {
            size: { type: :string, nullable: true },
            price_cents: { type: :integer, nullable: true },
            # Echoed back so an editor can round-trip a non-USD row
            # instead of rewriting it to the default on save.
            currency: { type: :string }
          }
        }
      },
      created_at: { type: :string, format: "date-time" }
    }
  }
end

def admin_user_row_schema
  {
    type: :object,
    required: %w[id email handle is_admin is_super_admin],
    properties: {
      id:           { type: :string, format: :uuid },
      email:        { type: :string },
      handle:       { type: :string },
      display_name: { type: :string, nullable: true },
      provider:     { type: :string, nullable: true },
      is_admin:     { type: :boolean },
      # Read-only here. PATCH cannot set it, and refuses to demote an
      # account that has it — surfaced so the list can say why.
      is_super_admin: { type: :boolean },
      created_at:   { type: :string, format: "date-time" },
      reviews_count:        { type: :integer },
      ingestion_runs_count: { type: :integer }
    }
  }
end

RSpec.describe "admin/management", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/admin/restaurants" do
    get("List/search restaurants (any status)") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :q, in: :query, type: :string, required: false
      parameter name: :status, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[draft published closed] }
      parameter name: :filter, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[community_published] }
      parameter name: :city_id, in: :query, type: :string, required: false
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "restaurants + pagination") do
        schema type: :object,
               required: %w[restaurants pagination],
               properties: {
                 restaurants: { type: :array, items: admin_restaurant_row_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:q) { nil }
        let(:status) { nil }
        let(:filter) { nil }
        let(:city_id) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        before { create(:restaurant, :published) }
        run_test!
      end

      response(404, "authenticated but not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:q) { nil }
        let(:status) { nil }
        let(:filter) { nil }
        let(:city_id) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/admin/restaurants/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    get("Restaurant detail + per-confidence item counts") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "the restaurant") do
        schema admin_restaurant_row_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:restaurant, :published).id }
        run_test!
      end
    end

    patch("Update fields + status (slug immutable)") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          name:    { type: :string },
          about:   { type: :string },
          website: { type: :string },
          phone:   { type: :string },
          status:  { type: :string, enum: %w[draft published closed] }
        }
      }

      response(200, "the updated restaurant") do
        schema admin_restaurant_row_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:restaurant, :published).id }
        let(:body) { { status: "closed" } }
        run_test!
      end

      response(422, "immutable slug change or invalid status") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:restaurant, :published).id }
        let(:body) { { slug: "renamed" } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/restaurants/{restaurant_id}/items" do
    parameter name: :restaurant_id, in: :path, type: :string, format: :uuid

    get("List a restaurant's items — every status") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :status, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[draft published removed] }
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "items + pagination") do
        schema type: :object,
               required: %w[items pagination],
               properties: {
                 items: { type: :array, items: admin_item_row_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:restaurant_id) do
          restaurant = create(:restaurant, :published)
          create(:item, restaurant: restaurant, status: "removed")
          restaurant.id
        end
        let(:status) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/admin/items/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    patch("Update name / description / status (removed = unpublish)") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        description: "Deep-edit a live dish. Absent keys are left alone; an explicit " \
                     "empty array clears that facet. Ingredient/tag joins are synced " \
                     "from slug lists and land confidence: confirmed, source: human " \
                     "(an admin IS the trusted source). `confidence` itself and the " \
                     "denormalized id arrays are deliberately not accepted — " \
                     "confidence stays on the promote/confirm_community rails.",
        properties: {
          name:            { type: :string },
          description:     { type: :string, nullable: true,
                             description: "null clears it; '' would store an empty string" },
          status:          { type: :string, enum: %w[draft published removed] },
          menu_section_id: { type: :string, format: :uuid, nullable: true,
                             description: "must belong to this item's restaurant (422 otherwise)" },
          position:        { type: :integer,
                             description: "Position within the menu section for ordering" },
          ingredient_slugs: {
            type: :array,
            description: "Complete list; unknown slugs 422 with the offenders.",
            items: { type: :string }
          },
          tag_slugs: { type: :array, items: { type: :string } },
          variants: {
            type: :array,
            description: "Replaced wholesale; array order becomes position. A row may " \
                         "carry a size with no price (\"Large — market price\"); rows " \
                         "with neither are dropped.",
            items: {
              type: :object,
              properties: {
                size:        { type: :string, nullable: true },
                price_cents: { type: :integer, nullable: true },
                currency:    { type: :string }
              }
            }
          },
          modifiers: {
            type: :array,
            description: "Replaced wholesale. kind defaults to addition.",
            items: {
              type: :object,
              required: %w[name],
              properties: {
                name:        { type: :string },
                kind:        { type: :string, enum: %w[choice addition side] },
                price_cents: { type: :integer, nullable: true }
              }
            }
          }
        }
      }

      response(200, "the updated item") do
        schema admin_item_row_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:item).id }
        let(:body) { { status: "removed" } }
        run_test!
      end

      response(422, "invalid_status, unknown_ingredient_slugs / unknown_tag_slugs, or foreign_menu_section") do
        schema type: :object,
               properties: {
                 error: { type: :string },
                 slugs: { type: :array, items: { type: :string } }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:item).id }
        let(:body) { { ingredient_slugs: ["no-such-ingredient"] } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/users" do
    get("List/search users") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :q, in: :query, type: :string, required: false,
                description: "ILIKE against email, handle, display_name"
      parameter name: :is_admin, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[true] }
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "users + pagination") do
        schema type: :object,
               required: %w[users pagination],
               properties: {
                 users: { type: :array, items: admin_user_row_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:q) { nil }
        let(:is_admin) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/admin/users/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    patch("Partial update: is_admin toggle and/or handle edit") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        # Each field applies only when present; a body with neither is
        # refused (no_supported_fields).
        properties: {
          is_admin: { type: :boolean },
          handle:   { type: :string, pattern: "^[a-z0-9_]{3,30}$" }
        }
      }

      response(200, "the updated user") do
        schema admin_user_row_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:user).id }
        let(:body) { { is_admin: true, handle: "renamed_by_admin" } }
        run_test! do
          expect(User.find(id).handle).to eq("renamed_by_admin")
        end
      end

      response(422, "self-demotion refused, invalid/taken handle, or empty body") do
        schema "$ref" => "#/components/schemas/Error"
        let(:account) { create(:user, :admin) }
        let(:Authorization) { bearer_for(account) }
        let(:id)   { account.id }
        let(:body) { { is_admin: false } }
        run_test!
      end
    end
  end
end
