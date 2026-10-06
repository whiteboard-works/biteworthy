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
    expect(result.location_pages.map { |c| c[:url] }).to eq(["https://caracasgrillutah.com/locations"])
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
end
