# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ingestion::SiteDiscoverer do
  let(:home) { "https://caracasgrillutah.com/" }

  def stub_page(url, body, content_type: "text/html")
    stub_request(:get, url).to_return(
      status: 200, body: body, headers: { "Content-Type" => content_type }
    )
  end

  it "collects same-origin menu links and ignores DoorDash and other hosts" do
    stub_page(home, <<~HTML)
      <html><body>
        <a href="/menu">Dinner menu</a>
        <a href="/menus/lunch.pdf">Lunch PDF</a>
        <a href="https://www.doordash.com/store/caracas">Order on DoorDash</a>
        <a href="https://other.example/menu">Someone else</a>
        <a href="/locations">Our locations</a>
      </body></html>
    HTML

    result = described_class.call(home)

    expect(result.menu_candidates.map { |c| c[:url] }).to contain_exactly(
      "https://caracasgrillutah.com/menu",
      "https://caracasgrillutah.com/menus/lunch.pdf"
    )
    expect(result.menu_candidates.find { |c| c[:url].end_with?(".pdf") }[:kind]).to eq("pdf")
    expect(result.location_pages.map { |c| c[:url] }).to eq([ "https://caracasgrillutah.com/locations" ])
  end

  it "reads location candidates from JSON-LD and does not invent extras" do
    stub_page(home, <<~HTML)
      <html><head>
        <script type="application/ld+json">
          {
            "@graph": [
              {
                "@type": "Restaurant",
                "name": "Caracas Grill — Woodbine",
                "telephone": "801-555-0100",
                "address": {
                  "@type": "PostalAddress",
                  "streetAddress": "1243 E 2100 S",
                  "addressLocality": "Salt Lake City",
                  "addressRegion": "UT",
                  "postalCode": "84106"
                },
                "openingHoursSpecification": {
                  "@type": "OpeningHoursSpecification",
                  "dayOfWeek": "https://schema.org/Monday",
                  "opens": "11:00:00",
                  "closes": "21:00"
                }
              },
              { "@type": "WebSite", "name": "Caracas Grill" }
            ]
          }
        </script>
      </head><body><p>Welcome. Also we have a Riverton kitchen — do not invent that from this sentence.</p></body></html>
    HTML

    result = described_class.call(home)
    spot = result.location_candidates.sole

    expect(spot[:name]).to eq("Caracas Grill — Woodbine")
    expect(spot[:street]).to eq("1243 E 2100 S")
    expect(spot[:city]).to eq("Salt Lake City")
    expect(spot[:region]).to eq("UT")
    expect(spot[:postal_code]).to eq("84106")
    expect(spot[:phone]).to eq("801-555-0100")
    expect(spot[:hours]).to eq([ { day_of_week: 1, opens_at: "11:00", closes_at: "21:00" } ])
    expect(result.location_candidates.size).to eq(1)
  end

  it "treats a PDF URL as the menu candidate" do
    stub_page("#{home}menu.pdf", "%PDF-1.4 fake", content_type: "application/pdf")

    result = described_class.call("#{home}menu.pdf")

    expect(result.menu_candidates).to eq([
      { url: "#{home}menu.pdf", kind: "pdf", label: "menu.pdf" }
    ])
    expect(result.location_candidates).to be_empty
  end

  it "refuses a forbidden host before fetching" do
    expect { described_class.call("https://www.doordash.com/store/x") }
      .to raise_error(UrlFetcher::FetchError, /forbidden_host/)
    expect(a_request(:get, /doordash/)).not_to have_been_made
  end

  it "picks up same-origin menu and location paths from data-href and location.href" do
    stub_page(home, <<~HTML)
      <html><body>
        <button data-href="/menu">View menu</button>
        <button onclick="location.href='/hours-locations'">Hours & Locations</button>
      </body></html>
    HTML

    result = described_class.call(home)

    expect(result.menu_candidates.map { |c| c[:url] }).to eq([ "https://caracasgrillutah.com/menu" ])
    expect(result.location_pages.map { |c| c[:url] }).to eq(
      [ "https://caracasgrillutah.com/hours-locations" ]
    )
    expect(a_request(:get, "https://caracasgrillutah.com/robots.txt")).not_to have_been_made
  end

  it "reads menu and location paths from sitemap.xml when the HTML is empty and robots allows" do
    stub_page(home, "<html><body>Welcome</body></html>")
    stub_page("https://caracasgrillutah.com/robots.txt", "User-agent: *\nAllow: /\n")
    stub_page("https://caracasgrillutah.com/sitemap.xml", <<~XML, content_type: "application/xml")
      <?xml version="1.0"?>
      <urlset>
        <url><loc>https://caracasgrillutah.com/menu</loc></url>
        <url><loc>https://caracasgrillutah.com/locations</loc></url>
      </urlset>
    XML

    result = described_class.call(home)

    expect(result.menu_candidates.map { |c| c[:url] }).to eq([ "https://caracasgrillutah.com/menu" ])
    expect(result.location_pages.map { |c| c[:url] }).to eq([ "https://caracasgrillutah.com/locations" ])
  end

  it "does not fetch sitemap.xml when robots.txt disallows it" do
    stub_page(home, "<html><body>Welcome</body></html>")
    stub_page("https://caracasgrillutah.com/robots.txt", "User-agent: *\nDisallow: /\n")

    result = described_class.call(home)

    expect(result.menu_candidates).to be_empty
    expect(result.location_pages).to be_empty
    expect(a_request(:get, "https://caracasgrillutah.com/sitemap.xml")).not_to have_been_made
  end

  it "splits a single-string JSON-LD address and keeps the raw string" do
    stub_page(home, <<~HTML)
      <html><head>
        <script type="application/ld+json">
          {"@type":"Restaurant","name":"Chimayo","address":"123 Canyon Rd, Santa Fe, NM 87501"}
        </script>
      </head><body></body></html>
    HTML

    spot = described_class.call(home).location_candidates.sole

    expect(spot).to include(
      name: "Chimayo", street: "123 Canyon Rd", city: "Santa Fe",
      region: "NM", postal_code: "87501", raw: "123 Canyon Rd, Santa Fe, NM 87501"
    )
  end

  it "splits a PostalAddress that stuffed the whole line into streetAddress" do
    stub_page(home, <<~HTML)
      <html><head>
        <script type="application/ld+json">
          {
            "@type":"Restaurant","name":"Chimayo",
            "address":{"@type":"PostalAddress","streetAddress":"123 Canyon Rd, Santa Fe, NM 87501, USA"}
          }
        </script>
      </head><body></body></html>
    HTML

    spot = described_class.call(home).location_candidates.sole

    expect(spot).to include(
      street: "123 Canyon Rd", city: "Santa Fe", region: "NM",
      postal_code: "87501", country: "USA",
      raw: "123 Canyon Rd, Santa Fe, NM 87501, USA"
    )
  end
end
