require "rails_helper"

# WBW-247 — one writer for moving a restaurant between cities. The
# restaurant slug is the public lookup key, so it must not change; the
# destination must already exist in the same state and country.
RSpec.describe Restaurants::ReassignCity do
  let!(:ogden)  { create(:city, slug: "ogden",  name: "Ogden",  region: "Utah", country: "US") }
  let!(:draper) { create(:city, slug: "draper", name: "Draper", region: "Utah", country: "US") }
  let(:restaurant) { create(:restaurant, :published, city: ogden, slug: "laan-thai-restaurant") }

  def call(city) = described_class.call(restaurant: restaurant, city: city)

  it "reassigns by slug and leaves the restaurant slug alone" do
    result = call("draper")

    expect(result).to eq(restaurant)
    expect(restaurant.reload).to have_attributes(city_id: draper.id, slug: "laan-thai-restaurant")
    expect(restaurant.web_path).to eq("/restaurants/usa/utah/draper/laan-thai-restaurant")
  end

  it "reassigns by UUID" do
    call(draper.id)

    expect(restaurant.reload.city_id).to eq(draper.id)
  end

  it "treats a display name as its parameterized slug (MCP city: \"Draper\")" do
    call("Draper")

    expect(restaurant.reload.city.slug).to eq("draper")
  end

  it "updates address city text to the new city's name when an address exists" do
    restaurant.addresses.create!(street: "123 Wall Ave", city: "Ogden", region: "Utah", country: "US")

    call("draper")

    expect(restaurant.addresses.sole).to have_attributes(city: "Draper", region: "Utah", country: "US")
  end

  it "clears stale geocoding so proximity search cannot keep the old city" do
    restaurant.addresses.create!(
      street: "123 Wall Ave", city: "Ogden", region: "Utah", country: "US",
      postal_code: "84401", latitude: 41.2230, longitude: -111.9738,
      map_provider_place_id: "ChIJogden"
    )

    call("draper")

    expect(restaurant.addresses.sole).to have_attributes(
      street: "123 Wall Ave", city: "Draper", region: "Utah", country: "US",
      postal_code: nil, latitude: nil, longitude: nil, map_provider_place_id: nil
    )
  end

  it "does not clear geocoding when the restaurant is already in that city" do
    restaurant.addresses.create!(
      street: "123 Wall Ave", city: "Ogden", region: "Utah", country: "US",
      postal_code: "84401", latitude: 41.2230, longitude: -111.9738,
      map_provider_place_id: "ChIJogden"
    )

    call("ogden")

    address = restaurant.addresses.sole
    expect(address.postal_code).to eq("84401")
    expect(address.latitude).to be_within(0.0001).of(41.2230)
    expect(address.longitude).to be_within(0.0001).of(-111.9738)
    expect(address.map_provider_place_id).to eq("ChIJogden")
  end

  it "raises UnknownCity when the city does not exist" do
    expect { call("atlantis") }.to raise_error(Restaurants::ReassignCity::UnknownCity)
    expect(restaurant.reload.city.slug).to eq("ogden")
  end

  it "raises RegionMismatch when the city is in another state" do
    create(:city, slug: "durango", name: "Durango", region: "Colorado", country: "US")

    expect { call("durango") }.to raise_error(Restaurants::ReassignCity::RegionMismatch, /Utah.*Colorado|same state/i)
    expect(restaurant.reload.city.slug).to eq("ogden")
  end

  it "raises RegionMismatch when the city is in another country" do
    create(:city, slug: "toronto", name: "Toronto", region: "Ontario", country: "CA")

    expect { call("toronto") }.to raise_error(Restaurants::ReassignCity::RegionMismatch)
    expect(restaurant.reload.city.slug).to eq("ogden")
  end

  it "raises RegionMismatch when either city has no region, even in the same country" do
    nowhere   = create(:city, slug: "nowhere",   name: "Nowhere",   region: nil, country: "US")
    elsewhere = create(:city, slug: "elsewhere", name: "Elsewhere", region: "",  country: "US")
    stray     = create(:restaurant, :published, city: nowhere, slug: "stray-diner")

    expect {
      described_class.call(restaurant: stray, city: "elsewhere")
    }.to raise_error(Restaurants::ReassignCity::RegionMismatch)
    expect(stray.reload.city_id).to eq(nowhere.id)
    expect(elsewhere.region).to eq("")
  end

  it "is a no-op when the target is already the restaurant's city, even with a blank region" do
    ghost = create(:city, slug: "ghost-town", name: "Ghost Town", region: nil, country: "US")
    stray = create(:restaurant, :published, city: ghost, slug: "ghost-diner")

    result = described_class.call(restaurant: stray, city: "ghost-town")

    expect(result).to eq(stray)
    expect(stray.reload.city_id).to eq(ghost.id)
  end
end
