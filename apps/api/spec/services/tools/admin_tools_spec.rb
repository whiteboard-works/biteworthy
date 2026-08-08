require "rails_helper"

# The admin tools write to data other people's safety decisions rest on.
# Two classes of property here: the audience gate (nothing below is
# reachable without is_admin) and, for each tool, the one rule that keeps
# a careless call from corrupting live data.
RSpec.describe "admin tools" do
  let(:admin)      { create(:user, is_admin: true) }
  let(:normal)     { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }

  def payload(response) = response.to_h[:structuredContent]
  def call(tool, user, **args) = tool.call(server_context: { user_id: user&.id }, **args)

  # Registry already hides these; Base re-checking is the defence in depth
  # for a caller working from a stale list.
  describe "the audience gate" do
    it "refuses every admin tool for a signed-in non-admin" do
      Tools::Registry.all.select { |tool| tool.audience == :admin }.each do |tool|
        response = call(tool, normal, restaurant: restaurant.slug)

        expect(payload(response)[:error]).to eq("forbidden"), "#{tool.name_value} let a non-admin through"
      end
    end

    it "refuses every admin tool anonymously" do
      Tools::Registry.all.select { |tool| tool.audience == :admin }.each do |tool|
        response = call(tool, nil, restaurant: restaurant.slug)

        expect(payload(response)[:error]).to eq("unauthorized"), "#{tool.name_value} let an anonymous caller through"
      end
    end
  end

  describe Tools::Restaurants::EditRestaurant do
    it "updates only what was passed" do
      call(described_class, admin, restaurant: restaurant.slug, about: "Tacos since 1994")

      expect(restaurant.reload.about).to eq("Tacos since 1994")
      expect(restaurant.name).to be_present
    end

    it "rejects a status outside the enum instead of writing it" do
      response = call(described_class, admin, restaurant: restaurant.slug, status: "amazing")

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(restaurant.reload.status).to eq("published")
    end

    # The slug is the public URL and the lookup key.
    it "does not expose the slug as editable" do
      expect(described_class.input_schema_value.to_h[:properties]).not_to have_key(:slug)
    end
  end

  describe Tools::Restaurants::ConfirmRestaurantData do
    let!(:item) { create(:item, :published, restaurant: restaurant) }
    let!(:ing)  { create(:ingredient, slug: "dairy-cheddar", name: "Cheddar", path: "dairy.cheddar") }

    before do
      ItemIngredient.create!(item: item, ingredient: ing, confidence: "suggested", source: "human")
    end

    it "graduates human-entered associations and the dishes that clear" do
      response = call(described_class, admin, restaurant: restaurant.slug)

      expect(payload(response)[:confirmed][:ingredients]).to eq(1)
      expect(item.reload.confidence).to eq("confirmed")
    end

    # Strict mode must never show a dish carrying an unverified AI guess.
    it "leaves a dish suggested while an AI association remains" do
      other = create(:ingredient, slug: "fish-anchovy", name: "Anchovy", path: "fish.anchovy")
      ItemIngredient.create!(item: item, ingredient: other, confidence: "suggested", source: "ai")

      call(described_class, admin, restaurant: restaurant.slug)

      expect(item.reload.confidence).to eq("suggested")
    end
  end

  describe Tools::Structure::GetMenuStructure do
    let!(:menu)    { create(:menu, restaurant: restaurant, name: "Main") }
    let!(:section) { create(:menu_section, menu: menu, name: "Tacos") }
    let!(:draft)   { create(:item, restaurant: restaurant, name: "Draft Taco", menu_section: section) }
    let!(:loose)   { create(:item, :published, restaurant: restaurant, name: "Unfiled Dish") }

    # The reason this is not get_menu: an admin has to reach dishes that
    # are not published yet.
    it "includes unpublished dishes" do
      response = call(described_class, admin, restaurant: restaurant.slug)

      names = payload(response)[:menus].flat_map { |m| m[:sections] }.flat_map { |s| s[:items] }.map { |i| i[:name] }
      expect(names).to include("<untrusted-content>Draft Taco</untrusted-content>")
    end

    it "surfaces dishes that belong to no section rather than dropping them" do
      response = call(described_class, admin, restaurant: restaurant.slug)

      expect(payload(response)[:unsectioned].map { |i| i[:id] }).to eq([loose.id])
    end
  end

  describe Tools::Structure::EditMenuStructure do
    let!(:menu)    { create(:menu, restaurant: restaurant, name: "Main") }
    let!(:section) { create(:menu_section, menu: menu, name: "Tacos") }
    let!(:item)    { create(:item, :published, restaurant: restaurant, menu_section: section) }

    it "creates a menu on a restaurant" do
      response = call(described_class, admin, action: "create_menu", restaurant: restaurant.slug, name: "Brunch")

      expect(payload(response)[:menu][:name]).to eq("Brunch")
    end

    # Losing a section must never lose the dishes.
    it "unsections a deleted section's dishes and reports how many" do
      response = call(described_class, admin, action: "delete_section", section_id: section.id)

      expect(payload(response)[:items_unsectioned]).to eq(1)
      expect(item.reload.menu_section_id).to be_nil
      expect(Item.exists?(item.id)).to be(true)
    end

    it "reports the same for a deleted menu's whole subtree" do
      response = call(described_class, admin, action: "delete_menu", menu_id: menu.id)

      expect(payload(response)[:sections_deleted]).to eq(1)
      expect(payload(response)[:items_unsectioned]).to eq(1)
      expect(Item.exists?(item.id)).to be(true)
    end

    # "abc".to_i is 0, which would silently sort a section to the top.
    it "rejects a non-numeric position rather than storing zero" do
      response = call(described_class, admin, action: "update_section", section_id: section.id, position: "first")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end

    it "names the missing argument instead of raising" do
      response = call(described_class, admin, action: "create_section")

      expect(payload(response)[:message]).to include("menu_id")
    end

    it "rejects an action it does not have" do
      response = call(described_class, admin, action: "delete_restaurant")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end
  end

  describe Tools::Structure::EditPlace do
    it "replaces the week and reads it back in worked order" do
      response = call(described_class, admin, restaurant: restaurant.slug, hours: [
        { day_of_week: 1, opens_at: "17:00", closes_at: "21:00" },
        { day_of_week: 1, opens_at: "11:00", closes_at: "14:00" },
        { day_of_week: 2 }
      ])

      monday = payload(response)[:place][:hours].select { |h| h[:day_of_week] == 1 }
      expect(monday.map { |h| h[:opens_at] }).to eq(["11:00", "17:00"])
      expect(payload(response)[:place][:hours].find { |h| h[:day_of_week] == 2 }[:opens_at]).to be_nil
    end

    # "25:99" casting silently to nil would publish the day as closed.
    it "rejects an impossible time rather than marking the day closed" do
      response = call(described_class, admin, restaurant: restaurant.slug,
                                              hours: [{ day_of_week: 1, opens_at: "25:99" }])

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(restaurant.hours).to be_empty
    end

    it "refuses a day that is both open and closed" do
      response = call(described_class, admin, restaurant: restaurant.slug, hours: [
        { day_of_week: 3, opens_at: "09:00", closes_at: "17:00" },
        { day_of_week: 3 }
      ])

      expect(payload(response)[:message]).to include("closed day has hours")
    end

    # A bad latitude casting to 0.0 puts the restaurant in the Atlantic.
    it "rejects a non-numeric coordinate" do
      response = call(described_class, admin, restaurant: restaurant.slug, latitude: "north")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end

    it "needs something to change" do
      response = call(described_class, admin, restaurant: restaurant.slug)

      expect(payload(response)[:error]).to eq("invalid_argument")
    end
  end

  describe Tools::Items::EditItem do
    let!(:dairy)  { create(:ingredient, slug: "dairy-cheddar", name: "Cheddar", path: "dairy.cheddar") }
    let!(:beef)   { create(:ingredient, slug: "meat-beef", name: "Beef", path: "meat.beef") }
    let(:item)    { create(:item, :published, restaurant: restaurant, ingredients: [dairy]) }

    # An admin IS the trusted source, so what they add outranks anything a
    # future scan says. Note Admin::ItemEditor only touches rows it adds —
    # restating a slug that is already attached does not upgrade it.
    it "adds associations as human-confirmed so a re-scan cannot overrule them" do
      call(described_class, admin, item_id: item.id, ingredient_slugs: %w[dairy-cheddar meat-beef])

      added = item.reload.item_ingredients.find { |row| row.ingredient_id == beef.id }
      expect(added).to have_attributes(confidence: "confirmed", source: "human")
    end

    # The slug list REPLACES; a model sending only the addition would drop
    # the allergen already recorded.
    it "replaces the ingredient list wholesale, keeping the denormalized array honest" do
      call(described_class, admin, item_id: item.id, ingredient_slugs: ["meat-beef"])

      expect(item.reload.denormalized_ingredient_ids).to eq([beef.id])
    end

    it "rejects the whole call on one unknown slug rather than dropping it" do
      response = call(described_class, admin, item_id: item.id,
                                              ingredient_slugs: %w[meat-beef not-a-thing])

      expect(payload(response)[:message]).to include("not-a-thing")
      expect(item.reload.denormalized_ingredient_ids).to eq([dairy.id])
    end

    # "4.50" would cast to 4 — a $4.50 taco priced at four cents.
    it "rejects a price that is not whole cents" do
      response = call(described_class, admin, item_id: item.id, variants: [{ size: "Large", price_cents: "4.50" }])

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(item.reload.item_variants).to be_empty
    end

    it "refuses to move a dish into another restaurant's section" do
      foreign = create(:menu_section, menu: create(:menu, restaurant: create(:restaurant, :published)))

      response = call(described_class, admin, item_id: item.id, menu_section_id: foreign.id)

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(item.reload.menu_section_id).to be_nil
    end

    # Strict-mode visibility rides on item confidence; it moves only on
    # the verify rails.
    it "does not expose confidence as editable" do
      expect(described_class.input_schema_value.to_h[:properties]).not_to have_key(:confidence)
    end
  end

  describe Tools::Taxonomy::CreateTaxonomyNode do
    let!(:parent) { create(:ingredient, slug: "dairy", name: "Dairy", path: "dairy") }

    it "creates an ingredient under an existing parent" do
      response = call(described_class, admin, kind: "ingredient", slug: "dairy-brie",
                                              name: "Brie", path: "dairy.brie", aliases: ["brie cheese"])

      expect(payload(response)[:node][:path]).to eq("dairy.brie")
      expect(Ingredient.find_by(slug: "dairy-brie").aliases).to eq(["brie cheese"])
    end

    # An orphan path breaks allergen derivation, which walks ancestry.
    it "refuses a path whose parent does not exist" do
      response = call(described_class, admin, kind: "ingredient", slug: "x", name: "X", path: "nope.x")

      expect(payload(response)[:message]).to include("nope")
      expect(Ingredient.exists?(slug: "x")).to be(false)
    end

    it "refuses a malformed path" do
      response = call(described_class, admin, kind: "ingredient", slug: "x", name: "X", path: "Dairy Brie")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end

    it "refuses a duplicate slug rather than raising" do
      response = call(described_class, admin, kind: "ingredient", slug: "dairy", name: "Dairy again", path: "dairy2")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end

    it "requires a family on a tag" do
      response = call(described_class, admin, kind: "tag", slug: "t", name: "T", path: "t")

      expect(payload(response)[:message]).to include("family")
    end
  end

  describe Tools::Taxonomy::EditTaxonomyNode do
    let!(:node) { create(:ingredient, slug: "legume-chickpea", name: "Chickpea", path: "legume.chickpea") }

    it "replaces the alias list, which is what makes menu text resolve" do
      call(described_class, admin, kind: "ingredient", slug: "legume-chickpea", aliases: %w[garbanzo ceci])

      expect(node.reload.aliases).to eq(%w[garbanzo ceci])
    end

    # Renaming a slug drops the joins that resolve by it.
    it "does not expose slug or path as editable" do
      properties = described_class.input_schema_value.to_h[:properties]

      expect(properties).not_to have_key(:path)
      expect(properties[:slug][:description]).to include("Which node")
    end

    it "needs something to change" do
      response = call(described_class, admin, kind: "ingredient", slug: "legume-chickpea")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end

    it "reports an unknown node as not found" do
      response = call(described_class, admin, kind: "ingredient", slug: "nope", name: "X")

      expect(payload(response)[:error]).to eq("not_found")
    end
  end

  describe Tools::Taxonomy::DeleteTaxonomyNode do
    let!(:node) { create(:ingredient, slug: "legume-chickpea", name: "Chickpea", path: "legume.chickpea") }

    it "deletes a node nothing references" do
      response = call(described_class, admin, kind: "ingredient", slug: "legume-chickpea")

      expect(payload(response)[:deleted]).to be(true)
      expect(Ingredient.exists?(node.id)).to be(false)
    end

    it "refuses while a dish references it, and says what is in the way" do
      item = create(:item, :published, restaurant: restaurant)
      ItemIngredient.create!(item: item, ingredient: node, confidence: "confirmed", source: "human")

      response = call(described_class, admin, kind: "ingredient", slug: "legume-chickpea")

      expect(payload(response)[:deleted]).to be(false)
      expect(payload(response)[:references][:items]).to eq(1)
      expect(Ingredient.exists?(node.id)).to be(true)
    end

    # Deleting a node out of somebody's avoid list weakens their filter
    # silently — profiles tolerate ids that no longer resolve.
    it "refuses while it sits in a user's avoid list" do
      normal.profile.update!(avoid_ingredient_ids: [node.id])

      response = call(described_class, admin, kind: "ingredient", slug: "legume-chickpea")

      expect(payload(response)[:references][:profiles]).to eq(1)
      expect(Ingredient.exists?(node.id)).to be(true)
    end
  end

  describe Tools::Moderation::ListModerationQueue do
    let(:item)   { create(:item, :published, restaurant: restaurant) }
    let!(:clean) { create(:review, user: normal, item: item, body: "solid") }
    let!(:spam)  { create(:review, user: create(:user), item: item, body: "buy at http://spam.example") }

    it "defaults to what is waiting on a decision" do
      response = call(described_class, admin)

      expect(payload(response)[:reviews].map { |r| r[:id] }).to eq([spam.id])
    end

    it "shows what has already been hidden on request" do
      spam.hide!(reason: "spam")

      response = call(described_class, admin, visibility: "hidden")

      expect(payload(response)[:reviews].map { |r| r[:id] }).to eq([spam.id])
    end

    it "fences the bodies it hands back" do
      response = call(described_class, admin)

      expect(payload(response)[:reviews].sole[:body]).to start_with("<untrusted-content>")
    end
  end

  describe Tools::Moderation::ModerateReview do
    let(:item)     { create(:item, :published, restaurant: restaurant) }
    let!(:review)  { create(:review, user: normal, item: item, body: "solid") }

    it "hides with a recorded reason and restores cleanly" do
      call(described_class, admin, review_id: review.id, action: "hide", reason: "spam")
      expect(review.reload).to be_hidden

      call(described_class, admin, review_id: review.id, action: "unhide")
      expect(review.reload).not_to be_hidden
    end

    it "refuses to hide without a reason the author can be shown" do
      response = call(described_class, admin, review_id: review.id, action: "hide")

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(review.reload).not_to be_hidden
    end

    # Hiding is reversible; only the author can actually destroy a review.
    it "leaves the row in place for the audit trail" do
      call(described_class, admin, review_id: review.id, action: "hide", reason: "abuse")

      expect(Review.exists?(review.id)).to be(true)
    end
  end

  describe Tools::Users::ListUsers do
    before { normal.update!(handle: "taco_fan", display_name: "Taco Fan") }

    it "finds an account by handle" do
      response = call(described_class, admin, q: "taco_fan")

      expect(payload(response)[:users].map { |u| u[:id] }).to eq([normal.id])
    end

    it "narrows to admins on request" do
      response = call(described_class, admin, admins_only: true)

      expect(payload(response)[:users].map { |u| u[:id] }).to eq([admin.id])
    end

    # An avoid list is a health record; it is not admin-readable.
    it "does not return dietary profiles" do
      response = call(described_class, admin)

      expect(payload(response)[:users].first.keys).not_to include(:avoid_ingredients, :profile)
    end
  end

  describe Tools::Users::SetUserRole do
    it "grants admin" do
      call(described_class, admin, user_id: normal.id, is_admin: true)

      expect(normal.reload.is_admin).to be(true)
    end

    # The guarantee that this tool can never leave the system with zero
    # admins.
    it "refuses to demote the caller" do
      response = call(described_class, admin, user_id: admin.id, is_admin: false)

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(admin.reload.is_admin).to be(true)
    end

    it "still lets one admin demote another" do
      other = create(:user, is_admin: true)

      call(described_class, admin, user_id: other.id, is_admin: false)

      expect(other.reload.is_admin).to be(false)
    end
  end
end
