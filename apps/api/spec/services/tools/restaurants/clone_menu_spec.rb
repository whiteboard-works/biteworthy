# frozen_string_literal: true

require "rails_helper"

# Multi-location import: scan and accept once, then copy published dishes
# onto empty siblings. Prices must survive. Community clones must not
# launder confirmed joins onto a location nobody verified — same trust
# as a community accept. Admin clones keep confidence as-is.
RSpec.describe Tools::Restaurants::CloneMenu do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:city) { create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "UT") }
  let(:source) { create(:restaurant, city: city, created_by_user_id: user.id, name: "Grill — Woodbine") }
  let(:target) { create(:restaurant, city: city, created_by_user_id: user.id, name: "Grill — Riverton") }
  let(:beef) { create(:ingredient, slug: "meat-beef", name: "Beef", path: "meat.beef") }
  let(:tag)  { create(:tag) }

  def payload(response) = response.to_h[:structuredContent]
  def call(**args)
    described_class.call(server_context: { user_id: user.id }, **args)
  end

  def seed_menu!(restaurant, name: "Pabellon Arepa", confidence: "confirmed")
    menu = restaurant.menus.find_by(name: "Main") || create(:menu, restaurant: restaurant, name: "Main")
    section = menu.menu_sections.find_by(name: "Arepa") ||
              create(:menu_section, menu: menu, name: "Arepa", position: 1)
    item = create(
      :item, :published,
      restaurant: restaurant, menu_section: section,
      name: name, description: "Shredded beef",
      confidence: confidence,
      position: 2, ingredients: [ beef ], tag_list: [ tag ]
    )
    ItemVariant.create!(item: item, size: "regular", price_cents: 1450, currency: "USD", position: 0)
    ItemModifier.create!(item: item, name: "Extra cheese", kind: "addition", price_cents: 200)
    item
  end

  it "copies published dishes, sections, and prices; community clone caps confidence at suggested" do
    seed_menu!(source)

    response = call(source_restaurant: source.slug, target_restaurant: target.slug)
    data = payload(response)

    expect(data[:cloned]).to be(true)
    expect(data[:items_cloned]).to eq(1)
    expect(data[:sections_cloned]).to eq(1)
    expect(data[:target][:status]).to eq("draft")
    expect(data[:next_step]).to include("stays a draft")
    expect(data[:next_step]).to include("will not appear in search")

    copy = target.items.published.sole
    expect(copy).to have_attributes(name: "Pabellon Arepa", description: "Shredded beef",
                                    confidence: "suggested", position: 2)
    expect(copy.menu_section.name).to eq("Arepa")
    expect(copy.item_variants.sole).to have_attributes(size: "regular", price_cents: 1450)
    expect(copy.item_modifiers.sole).to have_attributes(name: "Extra cheese", price_cents: 200)
    join = copy.item_ingredients.sole
    expect(join).to have_attributes(ingredient_id: beef.id, confidence: "suggested", source: "human")
    expect(copy.item_tags.sole).to have_attributes(tag_id: tag.id, confidence: "suggested")
    expect(copy.denormalized_ingredient_ids).to eq([ beef.id ])
    expect(source.items.published.sole.item_variants.sole.price_cents).to eq(1450)
    expect(source.items.published.sole.confidence).to eq("confirmed")
    expect(target.reload.status).to eq("draft")
  end

  it "does not raise a community clone above the source — inferred stays inferred" do
    seed_menu!(source, confidence: "inferred")

    call(source_restaurant: source.slug, target_restaurant: target.slug)

    copy = target.items.published.sole
    expect(copy.confidence).to eq("inferred")
    expect(copy.item_ingredients.sole.confidence).to eq("inferred")
    expect(copy.item_tags.sole.confidence).to eq("inferred")
  end

  it "publishes a community sibling when the source is already published" do
    source.update!(status: "published")
    seed_menu!(source)

    response = call(source_restaurant: source.slug, target_restaurant: target.slug)
    data = payload(response)

    expect(target.reload.status).to eq("published")
    expect(data[:target][:status]).to eq("published")
    expect(data[:next_step]).to include("now published")
    expect(target.items.published.sole.confidence).to eq("suggested")
  end

  it "lets an admin keep confirmed confidence as-is" do
    source.update!(status: "published")
    seed_menu!(source)
    admin = create(:user, is_admin: true)
    other = create(:restaurant, city: city, created_by_user_id: create(:user).id)

    response = described_class.call(
      server_context: { user_id: admin.id },
      source_restaurant: source.slug, target_restaurant: other.slug
    )

    expect(payload(response)[:cloned]).to be(true)
    copy = other.items.published.sole
    expect(copy.confidence).to eq("confirmed")
    expect(copy.item_ingredients.sole.confidence).to eq("confirmed")
    expect(other.reload.status).to eq("published")
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

  it "rolls a mid-clone failure back so the empty-menu guard does not block retry" do
    seed_menu!(source)
    seed_menu!(source, name: "Second Arepa")

    created = 0
    allow(Item).to receive(:create!).and_wrap_original do |orig, *args, **kwargs|
      created += 1
      raise StandardError, "simulated mid-clone failure" if created > 1

      orig.call(*args, **kwargs)
    end

    expect {
      Menus::Clone.call(source: source, target: target, actor: user)
    }.to raise_error(StandardError, "simulated mid-clone failure")

    expect(target.reload.items).to be_empty
    expect(target.menu_sections).to be_empty

    allow(Item).to receive(:create!).and_call_original

    result = Menus::Clone.call(source: source.reload, target: target.reload, actor: user)
    expect(result.items_cloned).to eq(2)
    expect(target.items.published.count).to eq(2)
  end

  it "copies dish photos onto new blobs so a later replace/purge cannot delete the other" do
    item = seed_menu!(source)
    item.photo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")),
      filename: "arepa.jpg",
      content_type: "image/jpeg"
    )
    original_bytes = item.photo.download
    source_blob_id = item.photo.blob.id

    call(source_restaurant: source.slug, target_restaurant: target.slug)

    copy = target.items.published.sole
    expect(copy.photo).to be_attached
    expect(copy.photo.blob.id).not_to eq(source_blob_id)
    expect(copy.photo.download).to eq(original_bytes)

    replacement = Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/test-image.jpg"),
      "image/jpeg"
    )
    Admin::ItemEditor.new(item).call(photo: replacement)
    perform_enqueued_jobs

    expect(ActiveStorage::Blob.exists?(source_blob_id)).to be(false)
    expect(copy.reload.photo).to be_attached
    expect(copy.photo.download).to eq(original_bytes)

    copy_blob_id = copy.photo.blob.id
    copy.photo.purge
    expect(item.reload.photo).to be_attached
    expect(item.photo.blob.id).not_to eq(copy_blob_id)
    expect(item.photo.blob.id).not_to eq(source_blob_id)
  end
end
