require "rails_helper"

# search_restaurants only sees published restaurants, so a brand-new city
# is invisible to it. This tool is how the chat finds that city's slug.
RSpec.describe Tools::Discovery::ListCities do
  it "lists a city with no published restaurants alongside one that has some" do
    durango = create(:city, slug: "durango", name: "Durango", region: "CO")
    create(:restaurant, :published, city: durango)
    create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "UT")

    cities = described_class.call(server_context: {}).to_h[:structuredContent][:cities]

    expect(cities.map { |c| [ c[:slug], c[:published_restaurants] ] })
      .to eq([ [ "durango", 1 ], [ "salt-lake-city", 0 ] ])
  end
end
