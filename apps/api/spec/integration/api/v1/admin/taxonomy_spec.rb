require "swagger_helper"

# Documents both taxonomy resources. The two are near-twins; the specs
# share shapes through these builders rather than components because
# the field sets diverge (aliases/allergen vs family/description).
def admin_ingredient_schema
  {
    type: :object,
    required: %w[id slug name path aliases allergen items_count],
    properties: {
      id:          { type: :string, format: :uuid },
      slug:        { type: :string },
      name:        { type: :string },
      path:        { type: :string, description: "ltree path; immutable after create" },
      aliases:     { type: :array, items: { type: :string } },
      allergen:    { type: :boolean },
      items_count: { type: :integer },
      created_at:  { type: :string, format: "date-time" }
    }
  }
end

def admin_tag_schema
  {
    type: :object,
    required: %w[id slug name path family items_count],
    properties: {
      id:          { type: :string, format: :uuid },
      slug:        { type: :string },
      name:        { type: :string },
      path:        { type: :string, description: "ltree path; immutable after create" },
      family:      { type: :string, enum: %w[diet allergen cuisine prep flavor] },
      description: { type: :string, nullable: true },
      items_count: { type: :integer },
      created_at:  { type: :string, format: "date-time" }
    }
  }
end

RSpec.describe "admin/taxonomy", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/admin/ingredients" do
    get("List ingredients in tree (path) order") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :q, in: :query, type: :string, required: false,
                description: "Substring match on name or aliases"
      parameter name: :limit, in: :query, type: :integer, required: false,
                description: "Default 100, max 500"
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "ingredients + pagination") do
        schema type: :object,
               required: %w[ingredients pagination],
               properties: {
                 ingredients: { type: :array, items: admin_ingredient_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:q) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        before { create(:ingredient) }
        run_test!
      end

      response(404, "authenticated but not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:q) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        run_test!
      end
    end

    post("Create an ingredient (parent path must exist)") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[slug name path],
        properties: {
          slug:     { type: :string },
          name:     { type: :string },
          path:     { type: :string, description: "ltree labels: [a-z0-9_], dot-separated" },
          aliases:  { type: :array, items: { type: :string } },
          allergen: { type: :boolean }
        }
      }

      response(201, "the created ingredient") do
        schema admin_ingredient_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:body) { { slug: "spice-sumac", name: "Sumac", path: "spice_sumac" } }
        run_test!
      end

      response(422, "invalid_path, parent_missing, or model validation failure") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:body) { { slug: "x", name: "X", path: "ghost.x" } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/ingredients/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    patch("Update name / aliases / allergen (slug + path immutable)") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          name:     { type: :string },
          aliases:  { type: :array, items: { type: :string } },
          allergen: { type: :boolean }
        }
      }

      response(200, "the updated ingredient") do
        schema admin_ingredient_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:ingredient).id }
        let(:body) { { name: "Renamed" } }
        run_test!
      end

      response(422, "attempted slug/path change") do
        schema type: :object,
               properties: {
                 error:  { type: :string },
                 fields: { type: :array, items: { type: :string } }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:ingredient).id }
        let(:body) { { slug: "renamed-slug" } }
        run_test!
      end
    end

    delete("Delete an unreferenced leaf") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(204, "deleted") do
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:ingredient).id }
        run_test!
      end

      response(409, "still referenced — refused with per-source counts") do
        schema type: :object,
               required: %w[error references],
               properties: {
                 error: { type: :string },
                 references: {
                   type: :object,
                   required: %w[descendants items presets profiles],
                   properties: {
                     descendants: { type: :integer },
                     items:       { type: :integer },
                     presets:     { type: :integer },
                     profiles:    { type: :integer }
                   }
                 }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) do
          ingredient = create(:ingredient)
          ItemIngredient.create!(item: create(:item), ingredient: ingredient,
                                 confidence: "confirmed", source: "human")
          ingredient.id
        end
        run_test!
      end
    end
  end

  path "/api/v1/admin/tags" do
    get("List tags in tree (path) order") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :q, in: :query, type: :string, required: false
      parameter name: :family, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[diet allergen cuisine prep flavor] }
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "tags + pagination") do
        schema type: :object,
               required: %w[tags pagination],
               properties: {
                 tags: { type: :array, items: admin_tag_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:q) { nil }
        let(:family) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        before { create(:tag) }
        run_test!
      end
    end

    post("Create a tag (parent path must exist)") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[slug name path family],
        properties: {
          slug:        { type: :string },
          name:        { type: :string },
          path:        { type: :string },
          family:      { type: :string, enum: %w[diet allergen cuisine prep flavor] },
          description: { type: :string }
        }
      }

      response(201, "the created tag") do
        schema admin_tag_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:body) { { slug: "prep-smoked", name: "Smoked", path: "prep_smoked", family: "prep" } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/tags/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    patch("Update name / description (slug + path + family immutable)") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          name:        { type: :string },
          description: { type: :string }
        }
      }

      response(200, "the updated tag") do
        schema admin_tag_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:tag).id }
        let(:body) { { name: "Renamed" } }
        run_test!
      end
    end

    delete("Delete an unreferenced tag") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(204, "deleted") do
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:tag).id }
        run_test!
      end
    end
  end
end
