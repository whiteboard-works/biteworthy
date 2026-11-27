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
end
