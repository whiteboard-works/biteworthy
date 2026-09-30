# frozen_string_literal: true

require "rails_helper"

# A default for "nearby", set from a slug the model got from list_cities.
# Coarse by design: a city, never coordinates.
RSpec.describe Tools::Profile::SetHomeCity do
  let(:user)    { create(:user) }
  let!(:durango) { create(:city, slug: "durango", name: "Durango", region: "CO") }

  def call(**args)
    described_class.call(server_context: { user_id: user.id }, **args)
  end

  def payload(response) = response.to_h[:structuredContent]

  it "sets the caller's home city from a slug and says what it was before" do
    create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "UT")
    user.profile.update!(home_city: durango)

    result = payload(call(city_slug: "salt-lake-city"))

    expect(result).to eq(previous_home_city: "durango", home_city: { slug: "salt-lake-city", name: "Salt Lake City", region: "UT" })
    expect(user.profile.reload.home_city.slug).to eq("salt-lake-city")
  end

  it "refuses a slug it cannot find, pointing at list_cities" do
    response = call(city_slug: "atlantis")

    expect(response.to_h[:isError]).to be(true)
    expect(payload(response)[:message]).to include("list_cities")
    expect(user.profile.reload.home_city).to be_nil
  end

  it "needs a signed-in caller" do
    response = described_class.call(server_context: {}, city_slug: "durango")

    expect(response.to_h[:isError]).to be(true)
  end

  it "shows up in the profile snapshot the tools serialize" do
    call(city_slug: "durango")

    expect(Tools::Profile::Serializer.call(user.profile.reload)[:home_city])
      .to eq(slug: "durango", name: "Durango", region: "CO")
  end
end
