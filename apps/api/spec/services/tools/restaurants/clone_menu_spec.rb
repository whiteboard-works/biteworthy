# frozen_string_literal: true

require "rails_helper"

# Multi-location import: scan and accept once, then copy published dishes
# onto empty siblings. Prices, confidence, and source must survive — a
# clone that dropped curated prices or confirmed joins would be the
# wrong answer for Caracas-style hand imports.
RSpec.describe Tools::Restaurants::CloneMenu do
  let(:user) { create(:user) }
  let(:city) { create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "UT") }
  let(:source) { create(:restaurant, city: city, created_by_user_id: user.id, name: "Caracas Grill — Woodbine") }
  let(:target) { create(:restaurant, city: city, created_by_user_id: user.id, name: "Caracas Grill — Riverton") }
  let(:beef) { create(:ingredient, slug: "meat-beef", name: "Beef", path: "meat.beef") }
  let(:tag)  { create(:tag) }

  def payload(response) = response.to_h[:structuredContent]
  def call(**args)
    described_class.call(server_context: { user_id: user.id }, **args)
  end

  def seed_menu!(restaurant)
    menu = create(:menu, restaurant: restaurant, name: "Main")
    section = create(:menu_section, menu: menu, name: "Arepa", position: 1)
    item = create(
      :item, :published, :confirmed,
      restaurant: restaurant, menu_section: section,
      name: "Pabellon Arepa", description: "Shredded beef",
      position: 2, ingredients: [ beef ], tag_list: [ tag ]
    )
    ItemVariant.create!(item: item, size: "regular", price_cents: 1450, currency: "USD", position: 0)
    ItemModifier.create!(item: item, name: "Extra cheese", kind: "addition", price_cents: 200)
    item
  end

  it "copies published dishes, sections, prices, and join confidence onto an empty sibling" do
    seed_menu!(source)

    response = call(source_restaurant: source.slug, target_restaurant: target.slug)
    data = payload(response)

    expect(data[:cloned]).to be(true)
    expect(data[:items_cloned]).to eq(1)
    expect(data[:sections_cloned]).to eq(1)

    copy = target.items.published.sole
    expect(copy).to have_attributes(name: "Pabellon Arepa", description: "Shredded beef",
                                    confidence: "confirmed", position: 2)
    expect(copy.menu_section.name).to eq("Arepa")
    expect(copy.item_variants.sole).to have_attributes(size: "regular", price_cents: 1450)
    expect(copy.item_modifiers.sole).to have_attributes(name: "Extra cheese", price_cents: 200)
    join = copy.item_ingredients.sole
    expect(join).to have_attributes(ingredient_id: beef.id, confidence: "confirmed", source: "human")
    expect(copy.denormalized_ingredient_ids).to eq([ beef.id ])
    expect(source.items.published.sole.item_variants.sole.price_cents).to eq(1450)
  end

  it "refuses a target that already has dishes so a second clone cannot duplicate" do
    seed_menu!(source)
    create(:item, :published, restaurant: target, name: "Already here")

    response = call(source_restaurant: source.slug, target_restaurant: target.slug)

    expect(payload(response)[:error]).to eq("invalid_argument")
    expect(payload(response)[:message]).to include("already has dishes")
    expect(target.items.count).to eq(1)
  end

  it "does not let a stranger clone onto someone else's restaurant" do
    seed_menu!(source)
    stranger_spot = create(:restaurant, city: city, created_by_user_id: create(:user).id)

    response = call(source_restaurant: source.slug, target_restaurant: stranger_spot.slug)

    expect(payload(response)[:error]).to eq("invalid_argument")
    expect(stranger_spot.items).to be_empty
  end

  it "lets an admin clone a published menu onto a draft they did not create" do
    source.update!(status: "published")
    seed_menu!(source)
    admin = create(:user, is_admin: true)
    other = create(:restaurant, city: city, created_by_user_id: create(:user).id)

    response = described_class.call(
      server_context: { user_id: admin.id },
      source_restaurant: source.slug, target_restaurant: other.slug
    )

    expect(payload(response)[:cloned]).to be(true)
    expect(other.items.published.size).to eq(1)
  end
end
