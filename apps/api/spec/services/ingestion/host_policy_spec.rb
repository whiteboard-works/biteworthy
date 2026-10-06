# frozen_string_literal: true

require "rails_helper"

# The ToS line: we do not fetch DoorDash / order.online, Google Maps
# galleries, or Toast ordering HTML. Prompt text is not enough — every
# fetch path (UrlFetcher, start_menu_scan, discover) reads this.
RSpec.describe Ingestion::HostPolicy do
  describe ".forbidden?" do
    {
      "https://www.doordash.com/store/caracas" => true,
      "https://order.doordash.com/menu" => true,
      "https://order.online/store/123" => true,
      "https://www.order.online/store/123" => true,
      "https://www.toasttab.com/caracas-grill/v3" => true,
      "https://order.toasttab.com/online/caracas" => true,
      "https://maps.google.com/maps?q=caracas" => true,
      "https://www.google.com/maps/place/Caracas+Grill" => true,
      "https://www.google.co.uk/maps/place/Caracas" => true,
      "https://google.com/maps" => true,
      "https://maps.app.goo.gl/abc" => true,
      "https://lh3.googleusercontent.com/p/photo" => true,
      "https://caracasgrillutah.com/menu" => false,
      "https://caracasgrillutah.com/menu.pdf" => false,
      "https://example.com/menu" => false,
      "https://notdoordash.com/menu" => false,
      "https://www.google.com/search?q=menu" => false
    }.each do |url, blocked|
      it "#{blocked ? 'refuses' : 'allows'} #{url}" do
        expect(described_class.forbidden?(url)).to eq(blocked)
      end
    end
  end

  it "explains what to do instead" do
    refusal = described_class.refusal("https://www.doordash.com/store/x")

    expect(refusal[:forbidden]).to be(true)
    expect(refusal[:host]).to eq("www.doordash.com")
    expect(refusal[:next_step]).to include("own website")
    expect(refusal[:next_step]).to include("paste")
  end

  describe ".storefront?" do
    it "flags a DoorDash CDN script as a storefront" do
      body = '<script src="https://web-static.cdn4dd.com/app.js"></script>'

      expect(described_class.storefront?({}, body)).to be(true)
    end

    it "flags a Toast storefront cookie" do
      headers = { "set-cookie" => "toast_session=abc; Path=/" }

      expect(described_class.storefront?(headers, "<html></html>")).to be(true)
    end

    it "flags an x-dd- response header" do
      headers = { "x-dd-bff" => "storefront" }

      expect(described_class.storefront?(headers, "<html></html>")).to be(true)
    end

    it "does not flag a restaurant page that only links to DoorDash" do
      body = '<a href="https://www.doordash.com/store/caracas">Order on DoorDash</a>'

      expect(described_class.storefront?({}, body)).to be(false)
    end
  end
end
