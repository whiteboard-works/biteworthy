# frozen_string_literal: true

require "rails_helper"

# The home city is a default, not a filter. "What's nearby" with no city
# named means the one they live in; a place asked for by name is found
# wherever it is.
RSpec.describe Tools::Discovery::SearchRestaurants do
  let!(:durango) { create(:city, slug: "durango", name: "Durango", region: "CO") }
  let!(:slc)     { create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "UT") }
  let!(:ninis)   { create(:restaurant, :published, city: durango, name: "Ninis Taqueria", slug: "ninis") }
  let!(:red_iguana) { create(:restaurant, :published, city: slc, name: "Red Iguana", slug: "red-iguana") }
  let(:user) { create(:user) }

  def payload(response) = response.to_h[:structuredContent]
  def names(response) = payload(response)[:restaurants].map { |r| r[:name] }

  it "lists everywhere for a caller with no home city" do
    expect(names(described_class.call(server_context: { user_id: user.id }))).to contain_exactly("Ninis Taqueria", "Red Iguana")
  end

  it "lists the caller's home city when no city is named, and says so" do
    user.profile.update!(home_city: slc)

    response = described_class.call(server_context: { user_id: user.id })

    expect(names(response)).to eq([ "Red Iguana" ])
    expect(payload(response)).to include(city: "salt-lake-city", city_source: "home_city")
  end

  # An empty answer must never read as "nowhere" when it means "not here".
  it "lets the model ask for everywhere, and says no city was applied" do
    user.profile.update!(home_city: slc)

    response = described_class.call(server_context: { user_id: user.id }, anywhere: true)

    expect(names(response)).to contain_exactly("Ninis Taqueria", "Red Iguana")
    expect(payload(response)).not_to have_key(:city)
  end

  it "refuses anywhere alongside a named city rather than quietly keeping the city" do
    response = described_class.call(server_context: { user_id: user.id }, city_slug: "durango", anywhere: true)

    expect(response.to_h[:isError]).to be(true)
    expect(payload(response)[:message]).to include("not both")
  end

  it "lets a named city win over the home city" do
    user.profile.update!(home_city: slc)

    response = described_class.call(server_context: { user_id: user.id }, city_slug: "durango")

    expect(names(response)).to eq([ "Ninis Taqueria" ])
    expect(payload(response)).to include(city: "durango", city_source: "argument")
  end

  it "never limits a search by name to the home city" do
    user.profile.update!(home_city: slc)

    expect(names(described_class.call(server_context: { user_id: user.id }, query: "ninis"))).to eq([ "Ninis Taqueria" ])
  end

  it "ranks by diet in the home city without being told the city" do
    user.profile.update!(home_city: durango)
    vegan = create(:dietary_profile, slug: "vegan", name: "Vegan")

    response = described_class.call(server_context: { user_id: user.id }, diet: vegan.slug)

    expect(response.to_h[:isError]).to be_falsey
    expect(names(response)).to eq([ "Ninis Taqueria" ])
    expect(payload(response)).to include(city: "durango", city_source: "home_city", diet: "vegan")
  end

  # Least privilege: the default reads the profile, so a credential that
  # was granted only discovery gets no default and no echo of the city.
  it "gives a discovery-only credential no home-city default" do
    user.profile.update!(home_city: slc)

    response = described_class.call(server_context: { user_id: user.id, scopes: [ "discovery:read" ] })

    expect(names(response)).to contain_exactly("Ninis Taqueria", "Red Iguana")
    expect(payload(response)).not_to have_key(:city)
  end

  it "leaves an anonymous caller unscoped" do
    expect(names(described_class.call(server_context: {}))).to contain_exactly("Ninis Taqueria", "Red Iguana")
  end
end
