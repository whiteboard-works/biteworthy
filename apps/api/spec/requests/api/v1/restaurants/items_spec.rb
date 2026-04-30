require "rails_helper"

RSpec.describe "GET /api/v1/restaurants/:id/items", type: :request do
  let(:restaurant) { create(:restaurant, :published) }

  # Build a small but realistic Durango menu: a beef taco (no dairy,
  # no shellfish), a cheese quesadilla (dairy), and a salmon bowl
  # (fish — flagged allergen). Reuses the curated factory data so
  # IDs read like real ingredients.
  let(:beef)   { create(:ingredient, slug: "meat-beef") }
  let(:cheese) { create(:ingredient, slug: "dairy-cheese") }
  let(:salmon) { create(:ingredient, slug: "fish-salmon") }

  let(:vegan_tag)         { create(:tag, slug: "diet-vegan") }
  let(:contains_dairy_tag){ create(:tag, slug: "allergen-contains-dairy") }

  let!(:carne_taco) do
    create(:item, :published, :confirmed,
           restaurant: restaurant, name: "Carne Asada Taco",
           ingredients: [beef], tag_list: [])
  end
  let!(:cheese_quesadilla) do
    create(:item, :published, :confirmed,
           restaurant: restaurant, name: "Cheese Quesadilla",
           ingredients: [cheese], tag_list: [contains_dairy_tag])
  end
  let!(:salmon_bowl) do
    create(:item, :published, :confirmed,
           restaurant: restaurant, name: "Salmon Bowl",
           ingredients: [salmon])
  end

  describe "with no profile (anonymous + no params)" do
    it "returns every published item, all visible" do
      get "/api/v1/restaurants/#{restaurant.id}/items"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      expect(body["items"].length).to eq(3)
      expect(body["items"].pluck("status").uniq).to eq(["visible"])
      expect(body["items"].pluck("reasons").flatten).to be_empty

      expect(body["filter"]).to include(
        "source"     => "none",
        "strictness" => "balanced"
      )
    end
  end

  describe "with ?profile=vegan" do
    let!(:vegan_preset) do
      preset = create(:dietary_profile, slug: "vegan")
      create(:dietary_profile_ingredient,
             dietary_profile: preset, ingredient: cheese, rule: "avoid")
      create(:dietary_profile_tag,
             dietary_profile: preset, tag: contains_dairy_tag, rule: "avoid")
      preset
    end

    it "hides dairy items with avoid_ingredient + avoid_tag reasons" do
      get "/api/v1/restaurants/#{restaurant.id}/items?profile=vegan"

      expect(response).to have_http_status(:ok)
      body  = response.parsed_body
      items = body["items"].index_by { |i| i["name"] }

      expect(items["Carne Asada Taco"]["status"]).to     eq("visible")
      expect(items["Salmon Bowl"]["status"]).to          eq("visible")
      expect(items["Cheese Quesadilla"]["status"]).to    eq("hidden")

      reason_kinds = items["Cheese Quesadilla"]["reasons"].map { |r| r["kind"] }
      expect(reason_kinds).to contain_exactly("avoid_ingredient", "avoid_tag")

      expect(body["filter"]).to include(
        "source"      => "preset",
        "preset_slug" => "vegan",
        "strictness"  => "balanced"
      )
    end

    it "enriches reasons with the human name + family for the chip (Phase 3.4)" do
      # The factory's `dairy-cheese` slug maps to name=Cheese, path=dairy.cheese.
      # The `allergen-contains-dairy` tag has family=allergen.
      get "/api/v1/restaurants/#{restaurant.id}/items?profile=vegan"

      reasons = response.parsed_body["items"]
                        .find { |i| i["name"] == "Cheese Quesadilla" }["reasons"]
                        .index_by { |r| r["kind"] }

      expect(reasons["avoid_ingredient"]).to include(
        "ingredient_id"     => cheese.id,
        "ingredient_name"   => "Cheese",
        "ingredient_family" => "dairy"
      )
      expect(reasons["avoid_tag"]).to include(
        "tag_id"     => contains_dairy_tag.id,
        "tag_name"   => "Contains Dairy",
        "tag_family" => "allergen"
      )
    end

    it "404s on an unknown profile slug" do
      get "/api/v1/restaurants/#{restaurant.id}/items?profile=no-such-thing"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "with ?strictness=strict" do
    let!(:suggested_item) do
      # Confidence 'suggested' (not 'confirmed') — should be hidden
      # in strict mode regardless of ingredient/tag avoid lists.
      create(:item, :published,
             restaurant: restaurant, name: "AI-Inferred Quinoa Bowl",
             confidence: "suggested")
    end

    it "hides items whose item-level confidence isn't 'confirmed'" do
      get "/api/v1/restaurants/#{restaurant.id}/items?strictness=strict"

      expect(response).to have_http_status(:ok)
      body  = response.parsed_body
      items = body["items"].index_by { |i| i["name"] }

      expect(items["Carne Asada Taco"]["status"]).to    eq("visible") # confirmed
      expect(items["AI-Inferred Quinoa Bowl"]["status"]).to eq("hidden")
      expect(body["filter"]["strictness"]).to eq("strict")

      reasons = items["AI-Inferred Quinoa Bowl"]["reasons"].map { |r| r["kind"] }
      expect(reasons).to include("unconfirmed_strict")
    end

    it "echoes 'relaxed' on filter.strictness when ?strictness=relaxed (Phase 3.5 toggle)" do
      get "/api/v1/restaurants/#{restaurant.id}/items?strictness=relaxed"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["filter"]["strictness"]).to eq("relaxed")
    end

    it "ignores garbage values and falls back to balanced (defense-in-depth for the toggle)" do
      get "/api/v1/restaurants/#{restaurant.id}/items?strictness=zomg-not-a-mode"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["filter"]["strictness"]).to eq("balanced")
    end
  end

  describe "with a signed-in user (no params)" do
    let(:user) { create(:user, password: "password123") }
    let(:headers) do
      token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
      { "Authorization" => "Bearer #{token}" }
    end

    it "uses the user's stored profile" do
      user.profile.update!(avoid_ingredient_ids: [salmon.id])

      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      expect(response).to have_http_status(:ok)
      body  = response.parsed_body
      items = body["items"].index_by { |i| i["name"] }

      expect(items["Salmon Bowl"]["status"]).to eq("hidden")
      expect(body["filter"]["source"]).to        eq("user_profile")
    end
  end

  describe "menu section payload (Phase 3.3)" do
    let(:menu)    { create(:menu, restaurant: restaurant) }
    let(:tacos)   { create(:menu_section, menu: menu, name: "Tacos", position: 0) }
    let(:bowls)   { create(:menu_section, menu: menu, name: "Bowls", position: 1) }

    let!(:sectioned_taco) do
      create(:item, :published, :confirmed,
             restaurant: restaurant, name: "Pollo Taco",
             menu_section: tacos, ingredients: [])
    end
    let!(:sectioned_bowl) do
      create(:item, :published, :confirmed,
             restaurant: restaurant, name: "Veggie Bowl",
             menu_section: bowls, ingredients: [])
    end

    it "exposes menu_section_id + menu_section_name on each item" do
      get "/api/v1/restaurants/#{restaurant.id}/items"

      expect(response).to have_http_status(:ok)
      items = response.parsed_body["items"].index_by { |i| i["name"] }

      expect(items["Pollo Taco"]).to include(
        "menu_section_id"   => tacos.id,
        "menu_section_name" => "Tacos"
      )
      expect(items["Veggie Bowl"]).to include(
        "menu_section_id"   => bowls.id,
        "menu_section_name" => "Bowls"
      )
      # Items without a section (the original three) carry nulls.
      expect(items["Carne Asada Taco"]).to include(
        "menu_section_id"   => nil,
        "menu_section_name" => nil
      )
    end
  end

  describe "with ?profile_token=… (Phase 3.9 shareable URLs)" do
    let(:token) do
      ProfileToken.encode(
        avoid_ingredient_ids: [cheese.id],
        avoid_tag_ids:        [],
        strictness:           "balanced"
      )
    end

    it "applies the encoded avoid_ingredient_ids" do
      get "/api/v1/restaurants/#{restaurant.id}/items?profile_token=#{token}"

      expect(response).to have_http_status(:ok)
      body  = response.parsed_body
      items = body["items"].index_by { |i| i["name"] }

      expect(items["Cheese Quesadilla"]["status"]).to eq("hidden")
      expect(items["Carne Asada Taco"]["status"]).to  eq("visible")
      expect(body["filter"]["source"]).to eq("profile_token")
    end

    it "lets ?strictness= override what the token encoded" do
      strict_token = ProfileToken.encode(
        avoid_ingredient_ids: [],
        avoid_tag_ids:        [],
        strictness:           "balanced"
      )
      get "/api/v1/restaurants/#{restaurant.id}/items?profile_token=#{strict_token}&strictness=strict"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["filter"]["strictness"]).to eq("strict")
    end

    it "422s on a malformed token" do
      get "/api/v1/restaurants/#{restaurant.id}/items?profile_token=not!base64@@@"
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(/Invalid profile_token/)
    end

    it "422s on a token with an unsupported schema version" do
      future = Base64.urlsafe_encode64(JSON.generate(v: 99, ai: [], at: [], s: "balanced"), padding: false)
      get "/api/v1/restaurants/#{restaurant.id}/items?profile_token=#{future}"
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "takes precedence over ?profile=<slug> when both are supplied" do
      preset = create(:dietary_profile, slug: "vegan")
      create(:dietary_profile_ingredient,
             dietary_profile: preset, ingredient: salmon, rule: "avoid")

      # Token avoids cheese, preset would avoid salmon — token wins.
      get "/api/v1/restaurants/#{restaurant.id}/items?profile_token=#{token}&profile=vegan"

      expect(response).to have_http_status(:ok)
      body  = response.parsed_body
      items = body["items"].index_by { |i| i["name"] }
      expect(items["Cheese Quesadilla"]["status"]).to eq("hidden") # token's effect
      expect(items["Salmon Bowl"]["status"]).to       eq("visible") # preset NOT applied
      expect(body["filter"]["source"]).to eq("profile_token")
    end
  end

  describe "lookup by slug (Phase 3.6)" do
    it "accepts the restaurant slug in place of the UUID" do
      get "/api/v1/restaurants/#{restaurant.slug}/items"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["restaurant_id"]).to eq(restaurant.id)
    end
  end

  describe "404 cases" do
    it "404s on a non-existent restaurant" do
      get "/api/v1/restaurants/00000000-0000-0000-0000-000000000000/items"
      expect(response).to have_http_status(:not_found)
    end

    it "404s on a draft restaurant (not published)" do
      draft = create(:restaurant) # default status = "draft"
      get "/api/v1/restaurants/#{draft.id}/items"
      expect(response).to have_http_status(:not_found)
    end
  end
end
