require "rails_helper"

# A city's slug goes into every restaurant URL in it, and a second
# spelling of a city we already cover splits its restaurants across two
# pages. The duplicate check and the admin gate are what this protects.
RSpec.describe Tools::Restaurants::CreateCity do
  let(:admin) { create(:user, :admin) }

  def payload(response) = response.to_h[:structuredContent]
  def call(user, **args) = described_class.call(server_context: { user_id: user.id }, **args)

  it "creates the city and hands back the slug create_restaurant needs" do
    response = call(admin, name: "Salt Lake City", region: "ut")

    expect(payload(response)[:created]).to be(true)
    expect(City.find_by!(slug: "salt-lake-city")).to have_attributes(name: "Salt Lake City", region: "UT", country: "US")
  end

  it "returns the existing city instead of creating a second one" do
    existing = create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "UT")

    response = call(admin, name: "salt lake city", region: "UT")

    expect(payload(response)).to include(created: false, reason: "already_exists")
    expect(payload(response)[:city][:id]).to eq(existing.id)
    expect(City.count).to eq(1)
  end

  # Older rows can have no region; the same name must still count as the
  # same city rather than slipping past the check as a second one.
  it "treats a same-named city with no region as the existing city" do
    existing = create(:city, slug: "durango", name: "Durango", region: nil)

    response = call(admin, name: "Durango", region: "CO")

    expect(payload(response)).to include(created: false, reason: "already_exists")
    expect(payload(response)[:city][:id]).to eq(existing.id)
    expect(City.count).to eq(1)
  end

  it "keeps a same-named city in another state apart instead of calling it a duplicate" do
    create(:city, slug: "springfield", name: "Springfield", region: "IL")

    response = call(admin, name: "Springfield", region: "MO")

    expect(payload(response)[:city][:slug]).to eq("springfield-mo")
  end

  it "rejects a region that is not a two-letter state code" do
    response = call(admin, name: "Salt Lake City", region: "Utah")

    expect(response.to_h[:isError]).to be(true)
    expect(City.count).to eq(0)
  end

  it "refuses a non-admin" do
    response = call(create(:user), name: "Salt Lake City", region: "UT")

    expect(response.to_h[:isError]).to be(true)
    expect(City.count).to eq(0)
  end
end
