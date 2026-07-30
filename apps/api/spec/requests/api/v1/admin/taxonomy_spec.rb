require "rails_helper"

# The taxonomy admin endpoints are the first HTTP write path the
# ingredient/tag catalog has ever had (previously Avo-only). The
# safety rails ARE the feature: slug/path/family immutability
# (ingestion payloads resolve by slug at promote time — a rename
# silently drops joins, an allergen P0; a path rename orphans ltree
# descendants), parent-must-exist on create, and referenced deletes
# refused with counts — deleting a node in someone's avoid list would
# silently weaken their safety filter.
RSpec.describe "Admin taxonomy CRUD", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "ingredients" do
    it "creates a node under an existing parent and lists it in tree order" do
      create(:ingredient, slug: "dairy", name: "Dairy", path: "dairy")

      post "/api/v1/admin/ingredients",
           params: { slug: "dairy-kefir", name: "Kefir", path: "dairy.kefir",
                     aliases: ["kephir"], allergen: true },
           headers: auth_headers_for(admin)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "slug" => "dairy-kefir", "path" => "dairy.kefir", "aliases" => ["kephir"],
        "allergen" => true, "items_count" => 0
      )

      get "/api/v1/admin/ingredients", headers: auth_headers_for(admin)
      expect(response.parsed_body["ingredients"].map { |i| i["path"] })
        .to eq(%w[dairy dairy.kefir])
    end

    it "refuses a child whose parent path does not exist" do
      post "/api/v1/admin/ingredients",
           params: { slug: "x", name: "X", path: "ghost.x" },
           headers: auth_headers_for(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "parent_missing", "parent" => "ghost")
    end

    it "refuses malformed ltree paths" do
      post "/api/v1/admin/ingredients",
           params: { slug: "x", name: "X", path: "Bad Path!" },
           headers: auth_headers_for(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("invalid_path")
    end

    it "updates name/aliases/allergen but rejects slug and path changes" do
      ingredient = create(:ingredient, slug: "chickpea", name: "Chickpea", path: "legume_chickpea")

      patch "/api/v1/admin/ingredients/#{ingredient.id}",
            params: { name: "Chickpeas", aliases: %w[garbanzo], allergen: false },
            headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)
      expect(ingredient.reload).to have_attributes(name: "Chickpeas", aliases: %w[garbanzo])

      patch "/api/v1/admin/ingredients/#{ingredient.id}",
            params: { slug: "garbanzo" },
            headers: auth_headers_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "immutable_field", "fields" => ["slug"])
      expect(ingredient.reload.slug).to eq("chickpea")
    end

    it "refuses to delete a referenced node, with per-source counts" do
      parent = create(:ingredient, slug: "dairy2", name: "Dairy2", path: "dairy2")
      create(:ingredient, slug: "dairy2-milk", name: "Milk", path: "dairy2.milk")
      item = create(:item)
      ItemIngredient.create!(item: item, ingredient: parent,
                             confidence: "confirmed", source: "human")
      profile = create(:user).profile
      profile.update!(avoid_ingredient_ids: [parent.id])

      delete "/api/v1/admin/ingredients/#{parent.id}", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq(
        "error" => "in_use",
        "references" => {
          "descendants" => 1, "items" => 1, "presets" => 0, "profiles" => 1
        }
      )
      expect(Ingredient.exists?(parent.id)).to be true
      expect(profile.reload.avoid_ingredient_ids).to eq([parent.id])
    end

    it "deletes an unreferenced leaf" do
      leaf = create(:ingredient, slug: "lonely", name: "Lonely", path: "lonely")

      delete "/api/v1/admin/ingredients/#{leaf.id}", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:no_content)
      expect(Ingredient.exists?(leaf.id)).to be false
    end

    it "404s non-admins on every verb" do
      ingredient = create(:ingredient)
      headers = auth_headers_for(create(:user))

      get "/api/v1/admin/ingredients", headers: headers
      expect(response).to have_http_status(:not_found)
      post "/api/v1/admin/ingredients", params: { slug: "x", name: "X", path: "x" }, headers: headers
      expect(response).to have_http_status(:not_found)
      delete "/api/v1/admin/ingredients/#{ingredient.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "tags" do
    it "creates, forbids family changes, and blocks referenced deletes" do
      post "/api/v1/admin/tags",
           params: { slug: "diet-carnivore", name: "Carnivore", path: "diet_carnivore",
                     family: "diet" },
           headers: auth_headers_for(admin)
      expect(response).to have_http_status(:created)
      tag = Tag.find(response.parsed_body["id"])

      patch "/api/v1/admin/tags/#{tag.id}", params: { family: "allergen" },
                                            headers: auth_headers_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["fields"]).to eq(["family"])
      expect(tag.reload.family).to eq("diet")

      profile = create(:user).profile
      profile.update!(prefer_tag_ids: [tag.id])
      delete "/api/v1/admin/tags/#{tag.id}", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["references"]).to include("profiles" => 1)
      expect(profile.reload.prefer_tag_ids).to eq([tag.id])
    end

    it "filters the index by family" do
      create(:tag, slug: "diet-x", name: "X", path: "diet_x", family: "diet")
      cuisine = create(:tag, slug: "cuisine-y", name: "Y", path: "cuisine_y", family: "cuisine")

      get "/api/v1/admin/tags", params: { family: "cuisine" }, headers: auth_headers_for(admin)

      expect(response.parsed_body["tags"].map { |t| t["id"] }).to eq([cuisine.id])
    end
  end
end
