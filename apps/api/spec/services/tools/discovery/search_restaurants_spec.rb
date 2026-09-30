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

  # Device location is per message and comes from the chat's tool
  # context, never from the model's arguments.
  describe "near_me" do
    # Downtown Durango, and two places at known distances from it.
    let(:here) { { "lat" => 37.275, "lng" => -107.880 } }
    let!(:close)  { create(:restaurant, :published, city: durango, name: "Zia Taqueria", slug: "zia") }
    let!(:bakery) { create(:restaurant, :published, city: slc, name: "Far Bakery", slug: "far-bakery") }

    before do
      durango.update!(latitude: 37.2753, longitude: -107.8801)
      slc.update!(latitude: 40.7608, longitude: -111.8910)
      close.addresses.create!(street: "1 Main Ave", latitude: 37.276, longitude: -107.880)
      ninis.addresses.create!(street: "9 College Dr", latitude: 37.300, longitude: -107.870)
      red_iguana.addresses.create!(street: "736 W North Temple", latitude: 40.772, longitude: -111.908)
    end

    def near(**args)
      described_class.call(server_context: { user_id: user.id, device_location: here }, near_me: true, **args)
    end

    it "sorts nearest first, drops what is out of range, and says how far" do
      response = near

      expect(names(response)).to eq([ "Zia Taqueria", "Ninis Taqueria" ])
      expect(payload(response)[:restaurants].first[:distance_km]).to eq(0.1)
      expect(payload(response)).to include(sorted_by: "distance", radius_km: 40.0)
    end

    # A thin coordinate backfill must read as "distance unknown", not
    # as nothing nearby.
    it "lists a restaurant without coordinates last when its city is in range" do
      create(:restaurant, :published, city: durango, name: "Aardvark Cafe", slug: "aardvark")

      expect(names(near)).to eq([ "Zia Taqueria", "Ninis Taqueria", "Aardvark Cafe" ])
      expect(payload(near)[:restaurants].last[:distance_km]).to be_nil
    end

    it "outranks the home city" do
      user.profile.update!(home_city: slc)

      expect(names(near)).to eq([ "Zia Taqueria", "Ninis Taqueria" ])
      expect(payload(near)).not_to have_key(:city_source)
    end

    it "sorts within a named city without a radius" do
      response = near(city_slug: "salt-lake-city")

      expect(names(response)).to eq([ "Red Iguana", "Far Bakery" ])
      expect(payload(response)).not_to have_key(:radius_km)
    end

    it "ranks a diet in the nearest city and adds distance" do
      vegan = create(:dietary_profile, slug: "vegan", name: "Vegan")

      response = near(diet: vegan.slug)

      expect(response.to_h[:isError]).to be_falsey
      expect(payload(response)).to include(city: "durango", city_source: "device_location")
      expect(payload(response)[:restaurants]).to all(have_key(:distance_km))
    end

    it "refuses when no location was shared, and says what to ask for" do
      response = described_class.call(server_context: { user_id: user.id }, near_me: true)

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:message]).to include("Use my location")
    end

    # Any address in range admits a restaurant, so its distance is to the
    # nearest one, whichever order the rows come back in.
    it "measures a multi-location restaurant to its nearest address" do
      ninis.addresses.create!(street: "Far away", latitude: 40.0, longitude: -105.0)
      ninis.addresses.create!(street: "Next door", latitude: 37.2755, longitude: -107.8801)

      expect(payload(near)[:restaurants].find { |r| r[:name] == "Ninis Taqueria" }[:distance_km]).to eq(0.1)
    end

    it "says so when a named city does not exist rather than returning nothing" do
      response = near(city_slug: "durango-co")

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:message]).to include("list_cities")
    end

    it "refuses near_me alongside anywhere" do
      expect(near(anywhere: true).to_h[:isError]).to be(true)
    end
  end
end
