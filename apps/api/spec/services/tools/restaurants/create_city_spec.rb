require "rails_helper"

# A city's slug and state go into every restaurant URL in it, and a
# second spelling of a city we already cover splits its restaurants
# across two pages. The duplicate check, the state normalization, and the
# admin gate are what this protects.
RSpec.describe Tools::Restaurants::CreateCity do
  let(:admin) { create(:user, :admin) }

  def payload(response) = response.to_h[:structuredContent]
  def call(user, **args) = described_class.call(server_context: { user_id: user.id }, **args)

  it "creates the city and hands back the slug create_restaurant needs" do
    response = call(admin, name: "Salt Lake City", region: "ut")

    expect(payload(response)[:created]).to be(true)
    expect(City.find_by!(slug: "salt-lake-city")).to have_attributes(name: "Salt Lake City", region: "Utah", country: "US")
  end

  # Production stores full names (Durango is "Colorado"); a code must
  # land the same way or the same state would render two ways in URLs.
  it "stores a state name however it was typed" do
    call(admin, name: "Park City", region: "utah")

    expect(City.find_by!(slug: "park-city").region).to eq("Utah")
  end

  it "returns the existing city instead of creating a second one" do
    existing = create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "Utah")

    response = call(admin, name: "salt lake city", region: "UT")

    expect(payload(response)).to include(created: false, reason: "already_exists")
    expect(payload(response)[:city][:id]).to eq(existing.id)
    expect(City.count).to eq(1)
  end

  it "recognizes a city stored with its state code as the same city" do
    existing = create(:city, slug: "durango", name: "Durango", region: "CO")

    response = call(admin, name: "Durango", region: "Colorado")

    expect(payload(response)[:city][:id]).to eq(existing.id)
    expect(City.count).to eq(1)
  end

  # Could be this city or a namesake elsewhere: neither creating a second
  # row nor claiming it is the same city is safe.
  [ nil, "", "Missoury" ].each do |bad_region|
    it "refuses while a same-named city has an unreadable state (#{bad_region.inspect})" do
      create(:city, slug: "springfield", name: "Springfield", region: bad_region)

      response = call(admin, name: "Springfield", region: "MO")

      expect(response.to_h[:isError]).to be(true)
      expect(City.count).to eq(1)
    end
  end

  it "matches an existing city whose state has stray whitespace" do
    existing = create(:city, slug: "moab", name: "Moab", region: "UT ")

    response = call(admin, name: "Moab", region: "Utah")

    expect(payload(response)[:city][:id]).to eq(existing.id)
  end

  it "treats punctuation variants of a name as the same city" do
    existing = create(:city, slug: "st-louis", name: "St. Louis", region: "Missouri")

    response = call(admin, name: "St Louis", region: "MO")

    expect(payload(response)[:city][:id]).to eq(existing.id)
  end

  it "treats an abbreviation of a city in the same state as that city" do
    existing = create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "Utah")

    response = call(admin, name: "SLC", region: "UT")

    expect(payload(response)[:city][:id]).to eq(existing.id)
    expect(City.count).to eq(1)
  end

  it "treats a civic abbreviation in the name as the same city" do
    existing = create(:city, slug: "fort-worth", name: "Fort Worth", region: "Texas")

    response = call(admin, name: "Ft. Worth", region: "TX")

    expect(payload(response)[:city][:id]).to eq(existing.id)
  end

  it "refuses an abbreviation while the full-named city has no state on file" do
    create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: nil)

    response = call(admin, name: "SLC", region: "UT")

    expect(response.to_h[:isError]).to be(true)
    expect(City.count).to eq(1)
  end

  it "refuses an abbreviation that could mean two cities in the state" do
    create(:city, slug: "santa-clara", name: "Santa Clara", region: "California")
    create(:city, slug: "santa-cruz", name: "Santa Cruz", region: "California")

    response = call(admin, name: "SC", region: "CA")

    expect(response.to_h[:isError]).to be(true)
    expect(City.count).to eq(2)
  end

  it "treats a dotted initialism as the same city" do
    existing = create(:city, slug: "washington-dc", name: "Washington DC", region: "District of Columbia")

    response = call(admin, name: "Washington, D.C.", region: "DC")

    expect(payload(response)[:city][:id]).to eq(existing.id)
  end

  [ "O'Fallon", "O’Fallon" ].each do |spelling|
    it "ignores the apostrophe in #{spelling}" do
      existing = create(:city, slug: "ofallon", name: "OFallon", region: "Missouri")

      response = call(admin, name: spelling, region: "MO")

      expect(payload(response)[:city][:id]).to eq(existing.id)
    end
  end

  it "numbers the slug when even the state-suffixed one is taken" do
    create(:city, slug: "springfield", name: "Springfield", region: "Illinois")
    create(:city, slug: "springfield-missouri", name: "Springfield Township", region: "Ohio")

    response = call(admin, name: "Springfield", region: "MO")

    expect(payload(response)[:city][:slug]).to eq("springfield-missouri-2")
  end

  it "keeps a same-named city in another state apart instead of calling it a duplicate" do
    create(:city, slug: "springfield", name: "Springfield", region: "Illinois")

    response = call(admin, name: "Springfield", region: "MO")

    expect(payload(response)[:city][:slug]).to eq("springfield-missouri")
  end

  it "rejects a region that is not a US state" do
    response = call(admin, name: "Salt Lake City", region: "Utha")

    expect(response.to_h[:isError]).to be(true)
    expect(City.count).to eq(0)
  end

  it "refuses a non-admin" do
    response = call(create(:user), name: "Salt Lake City", region: "UT")

    expect(response.to_h[:isError]).to be(true)
    expect(City.count).to eq(0)
  end
end
