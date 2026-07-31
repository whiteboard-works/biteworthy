require "rails_helper"

# Admin deep-edit is the "fix it at the source" counterpart to verify
# editing: once a dish is live, this is the only way to correct what it
# claims. The rules that protect allergy users are the point —
# admin-set joins land `confirmed`/`human` (so strict mode trusts
# them), removals go row-by-row so the denormalized arrays the filter
# query reads stay in sync, and `confidence` itself is unreachable
# from here.
RSpec.describe "Admin item deep edit", type: :request do
  let(:admin)      { create(:user, :admin) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:item)       { create(:item, restaurant: restaurant) }

  let!(:beef)   { create(:ingredient, slug: "meat-beef", name: "Beef") }
  let!(:tofu)   { create(:ingredient, slug: "soy-tofu", name: "Tofu") }
  let!(:vegan)  { create(:tag, slug: "diet-vegan", name: "Vegan", path: "diet_vegan", family: "diet") }

  def patch_item(payload)
    patch "/api/v1/admin/items/#{item.id}",
          params: payload.to_json,
          headers: auth_headers_for(admin).merge("Content-Type" => "application/json")
  end

  describe "ingredient + tag join sync" do
    it "adds joins as confirmed/human so strict mode trusts them" do
      patch_item(ingredient_slugs: %w[meat-beef], tag_slugs: %w[diet-vegan])

      expect(response).to have_http_status(:ok)
      expect(item.item_ingredients.pluck(:confidence, :source)).to eq([%w[confirmed human]])
      expect(item.item_tags.pluck(:confidence, :source)).to eq([%w[confirmed human]])
      expect(response.parsed_body["ingredients"].map { |i| i["slug"] }).to eq(%w[meat-beef])
      expect(response.parsed_body["tags"].first).to include("name" => "Vegan", "family" => "diet")
    end

    # THE P0. The filter query reads the denormalized items.ingredient_ids
    # COLUMN, not the join table — and `item.ingredient_ids` in Ruby is
    # the has_many-through reader, which shadows that column and would
    # pass even if the callbacks never ran. Read the raw attribute (and
    # re-run the actual filter predicate) so a removal that skipped the
    # after_destroy callbacks fails loudly instead of leaving an
    # allergen visible on a dish that no longer lists it.
    def denormalized_ingredient_ids
      item.reload.read_attribute(:ingredient_ids)
    end

    def filter_sees_ingredient?(ingredient)
      Item.where(id: item.id)
          .where("items.ingredient_ids && ARRAY[?]::uuid[]", ingredient.id)
          .exists?
    end

    it "keeps the denormalized column in sync on add AND remove" do
      patch_item(ingredient_slugs: %w[meat-beef soy-tofu])
      expect(denormalized_ingredient_ids).to contain_exactly(beef.id, tofu.id)
      expect(filter_sees_ingredient?(beef)).to be true

      patch_item(ingredient_slugs: %w[soy-tofu])

      expect(denormalized_ingredient_ids).to eq([tofu.id])
      expect(item.item_ingredients.count).to eq(1)
      # The assertion that actually matters: the filter no longer sees
      # beef on this dish.
      expect(filter_sees_ingredient?(beef)).to be false
    end

    it "keeps the denormalized tag column in sync too" do
      patch_item(tag_slugs: %w[diet-vegan])
      expect(item.reload.read_attribute(:tag_ids)).to eq([vegan.id])

      patch_item(tag_slugs: [])
      expect(item.reload.read_attribute(:tag_ids)).to eq([])
    end

    it "clears every chip when an explicit empty list is sent" do
      patch_item(ingredient_slugs: %w[meat-beef])
      expect(item.reload.read_attribute(:ingredient_ids)).to eq([beef.id])

      patch_item(ingredient_slugs: [])

      expect(response).to have_http_status(:ok)
      expect(item.reload.read_attribute(:ingredient_ids)).to eq([])
      expect(item.item_ingredients).to be_empty
    end

    it "leaves joins alone when the key is absent" do
      patch_item(ingredient_slugs: %w[meat-beef])
      patch_item(name: "Renamed only")

      expect(item.reload.read_attribute(:ingredient_ids)).to eq([beef.id])
      expect(item.name).to eq("Renamed only")
    end

    # Unlike the extractor's payloads (silently filtered), an admin typo
    # must not vanish into a no-op.
    it "422s an unknown slug and changes nothing" do
      patch_item(ingredient_slugs: %w[meat-beef ghost-ingredient])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq(
        "error" => "unknown_ingredient_slugs", "slugs" => ["ghost-ingredient"]
      )
      expect(item.reload.item_ingredients).to be_empty
    end

    it "never lets confidence be set directly" do
      patch_item(confidence: "confirmed", name: "Still suggested")

      expect(response).to have_http_status(:ok)
      expect(item.reload.confidence).to eq("suggested")
    end
  end

  describe "variants + modifiers" do
    it "replaces variants wholesale in payload order" do
      item.item_variants.create!(size: "old", price_cents: 100, position: 0)

      patch_item(variants: [
        { size: "small", price_cents: 650 },
        { size: "large", price_cents: 950 }
      ])

      expect(response).to have_http_status(:ok)
      expect(item.reload.item_variants.order(:position).pluck(:size, :price_cents))
        .to eq([["small", 650], ["large", 950]])
    end

    # "Large — market price" is a real menu row, and a re-scan apply
    # writes them (IngestionItem#apply_update! passes price_cents
    # through with no blank guard). If the editor dropped them, an admin
    # fixing a typo on a sibling row would silently delete one.
    it "keeps a size-only variant instead of dropping it" do
      patch_item(variants: [{ size: "Large" }, { size: "Small", price_cents: 500 }])

      expect(response).to have_http_status(:ok)
      expect(item.reload.item_variants.order(:position).pluck(:size, :price_cents))
        .to eq([["Large", nil], ["Small", 500]])
    end

    it "drops a wholly empty variant row and clears on an empty list" do
      patch_item(variants: [{ size: "", price_cents: "" }, { size: "ok", price_cents: 500 }])
      expect(item.reload.item_variants.pluck(:size)).to eq(["ok"])

      patch_item(variants: [])
      expect(item.reload.item_variants).to be_empty
    end

    it "replaces modifiers and defaults the kind to addition" do
      patch_item(modifiers: [
        { name: "Add avocado", price_cents: 200 },
        { name: "Side salad", kind: "side" }
      ])

      expect(response).to have_http_status(:ok)
      expect(item.reload.item_modifiers.order(:name).pluck(:name, :kind, :price_cents))
        .to eq([["Add avocado", "addition", 200], ["Side salad", "side", nil]])
      expect(response.parsed_body["modifiers"].map { |m| m["name"] })
        .to eq(["Add avocado", "Side salad"])
    end
  end

  describe "price floors" do
    # This endpoint writes to an ALREADY-published menu, so it needs at
    # least the floor the staged-edit path enforces.
    it "422s a negative or non-numeric variant price and writes nothing" do
      item.item_variants.create!(size: "regular", price_cents: 1_200, position: 0)

      patch_item(variants: [{ size: "neg", price_cents: -500 }])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "invalid_price_cents", "values" => ["-500"])

      patch_item(variants: [{ size: "junk", price_cents: "abc" }])
      expect(response).to have_http_status(:unprocessable_entity)

      # The live prices survived both attempts.
      expect(item.reload.item_variants.pluck(:size, :price_cents)).to eq([["regular", 1_200]])
    end

    it "422s a negative modifier price" do
      patch_item(modifiers: [{ name: "Add avocado", price_cents: -900 }])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(item.reload.item_modifiers).to be_empty
    end

    it "still allows a free (zero) price" do
      patch_item(variants: [{ size: "free", price_cents: 0 }])

      expect(response).to have_http_status(:ok)
      expect(item.reload.item_variants.pluck(:price_cents)).to eq([0])
    end
  end

  describe "menu section moves" do
    it "moves an item into a section of its own restaurant and back out" do
      section = create(:menu_section, menu: create(:menu, restaurant: restaurant))

      patch_item(menu_section_id: section.id)
      expect(item.reload.menu_section_id).to eq(section.id)

      patch_item(menu_section_id: nil)
      expect(item.reload.menu_section_id).to be_nil
    end

    it "422s a section belonging to another restaurant" do
      foreign = create(:menu_section, menu: create(:menu, restaurant: create(:restaurant)))

      patch_item(menu_section_id: foreign.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("foreign_menu_section")
      expect(item.reload.menu_section_id).to be_nil
    end
  end

  it "404s non-admins" do
    patch "/api/v1/admin/items/#{item.id}",
          params: { name: "nope" }.to_json,
          headers: auth_headers_for(create(:user)).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:not_found)
    expect(item.reload.name).not_to eq("nope")
  end
end
