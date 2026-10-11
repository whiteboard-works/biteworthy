require "rails_helper"

# Location-based URLs — Restaurant#web_path is the single source of truth
# for the segment format every server-side caller (rswag serializers, claim
# URL builders, the web app) relies on. Lookup always resolves by the
# trailing slug; country/region/city are for humans/SEO only, which is why
# this spec pins the exact formatting rules rather than just "returns a
# string".
RSpec.describe Restaurant, type: :model do
  describe "#web_path" do
    it "lowercases the US country to usa and parameterizes the region" do
      city = create(:city, slug: "durango", region: "Colorado", country: "US")
      restaurant = create(:restaurant, city: city, slug: "rgp-s-wraps")

      expect(restaurant.web_path).to eq("/restaurants/usa/colorado/durango/rgp-s-wraps")
    end

    it "spells out a US state stored as a code" do
      city = create(:city, slug: "durango", region: "CO", country: "US")
      restaurant = create(:restaurant, city: city, slug: "rgp-s-wraps")

      expect(restaurant.web_path).to eq("/restaurants/usa/colorado/durango/rgp-s-wraps")
    end

    it "parameterizes a multi-word region" do
      city = create(:city, slug: "salt-lake-city", region: "Utah", country: "US")
      restaurant = create(:restaurant, city: city, slug: "some-diner")

      expect(restaurant.web_path).to eq("/restaurants/usa/utah/salt-lake-city/some-diner")
    end

    it "downcases a non-US country as-is" do
      city = create(:city, slug: "toronto", region: "Ontario", country: "CA")
      restaurant = create(:restaurant, city: city, slug: "poutine-place")

      expect(restaurant.web_path).to eq("/restaurants/ca/ontario/toronto/poutine-place")
    end

    it "falls back to na when the city has no region" do
      city = create(:city, slug: "nowhere", region: nil, country: "US")
      restaurant = create(:restaurant, city: city, slug: "somewhere-diner")

      expect(restaurant.web_path).to eq("/restaurants/usa/na/nowhere/somewhere-diner")
    end

    it "percent-encodes a slug with reserved characters and cleans the location segments" do
      city = build(:city, slug: "Salt Lake/City", region: "Utah", country: "US")
      restaurant = build(:restaurant, slug: "a b?#", city: city)

      expect(restaurant.web_path).to eq("/restaurants/usa/utah/salt-lake-city/a%20b%3F%23")
    end
  end
end

# Branding goes through Restaurants::Branding, which strips and re-encodes
# every image — but the model's own limits are the last line, so a blob
# attached by any other path still cannot exceed them.
RSpec.describe Restaurant, type: :model do
  describe "logo and banner validation" do
    it "rejects a non-image logo" do
      restaurant = build(:restaurant)
      restaurant.logo.attach(io: StringIO.new("%PDF-1.4"), filename: "menu.pdf", content_type: "application/pdf")

      expect(restaurant).not_to be_valid
      expect(restaurant.errors[:logo].sole).to include("must be one of")
    end

    it "rejects a banner over the size cap" do
      restaurant = build(:restaurant)
      restaurant.banner.attach(
        io: StringIO.new("x" * (HasPhotoValidation::MAX_PHOTO_BYTES + 1)),
        filename: "banner.jpg", content_type: "image/jpeg"
      )

      expect(restaurant).not_to be_valid
      expect(restaurant.errors[:banner].sole).to include("5 MB or smaller")
    end

    it "accepts a small JPEG logo" do
      restaurant = build(:restaurant)
      restaurant.logo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")),
        filename: "logo.jpg", content_type: "image/jpeg"
      )

      expect(restaurant).to be_valid
    end
  end
end
