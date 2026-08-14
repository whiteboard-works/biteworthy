require "rails_helper"

# The duplicate guard is the whole point of this tool. An agent that
# creates "Ninis Taqueria" next to "Ninis" splits a restaurant's menu in
# two and neither half is complete.
RSpec.describe Tools::Restaurants::CreateRestaurant do
  let(:user) { create(:user) }
  let!(:city) { create(:city, slug: "durango", name: "Durango", region: "CO") }

  def payload(response) = response.to_h[:structuredContent]
  def call(**args) = described_class.call(server_context: { user_id: user.id }, **args)

  it "creates a draft attributed to the caller" do
    response = call(name: "Ninis Taqueria", city_slug: "durango")

    restaurant = Restaurant.find(payload(response)[:restaurant][:id])
    expect(restaurant.status).to eq("draft")
    expect(restaurant.created_by_user_id).to eq(user.id)
    expect(payload(response)[:created]).to be(true)
  end

  it "attaches an address when one is given" do
    response = call(name: "Ninis Taqueria", city_slug: "durango", street: "123 Main Ave", postal_code: "81301")

    restaurant = Restaurant.find(payload(response)[:restaurant][:id])
    expect(restaurant.addresses.sole).to have_attributes(street: "123 Main Ave", city: "Durango", region: "CO")
  end

  it "stops at a likely duplicate and creates nothing" do
    create(:restaurant, name: "Marias Taco", slug: "marias-taco", city: city)

    response = call(name: "Maria's Tacos", city_slug: "durango")

    expect(payload(response)[:created]).to be(false)
    expect(payload(response)[:possible_duplicates].map { |c| c[:slug] }).to include("marias-taco")
    expect(Restaurant.where(name: "Maria's Tacos")).to be_empty
  end

  it "creates anyway once the user has looked at the candidates" do
    create(:restaurant, name: "Marias Taco", slug: "marias-taco", city: city)

    response = call(name: "Maria's Tacos", city_slug: "durango", force: true)

    expect(payload(response)[:created]).to be(true)
  end

  it "does not treat a genuinely different restaurant as a duplicate" do
    create(:restaurant, name: "Durango Bagel", slug: "durango-bagel", city: city)

    response = call(name: "Durango Diner", city_slug: "durango")

    expect(payload(response)[:created]).to be(true)
  end

  # The collision that actually happens is the same chain in two cities —
  # every town has a Taco Bell — and `taco-bell-2` is a URL that says
  # nothing about which one it is. The city is the disambiguator a person
  # would have reached for, so the generator reaches for it first.
  it "disambiguates a slug colliding across cities with the city name" do
    create(:restaurant, name: "Ninis", slug: "ninis-taqueria", city: create(:city, slug: "telluride"))

    response = call(name: "Ninis Taqueria", city_slug: "durango")

    expect(payload(response)[:restaurant][:slug]).to eq("ninis-taqueria-durango")
  end

  # Two of the same chain in ONE city is the case the city cannot settle.
  # Appending "durango" there would name what they have in common, so the
  # number is both the honest answer and the only distinguishing one.
  it "falls back to a number when the collision is inside one city" do
    create(:restaurant, name: "Ninis", slug: "ninis-taqueria", city: city)

    response = call(name: "Ninis Taqueria", city_slug: "durango", force: true)

    expect(payload(response)[:restaurant][:slug]).to eq("ninis-taqueria-2")
  end

  it "explains an unknown city instead of erroring out" do
    response = call(name: "Somewhere", city_slug: "atlantis")

    expect(payload(response)[:error]).to eq("invalid_argument")
    expect(payload(response)[:message]).to include("atlantis")
  end

  it "refuses an anonymous caller" do
    response = described_class.call(server_context: {}, name: "X", city_slug: "durango")

    expect(payload(response)[:error]).to eq("unauthorized")
  end
end
