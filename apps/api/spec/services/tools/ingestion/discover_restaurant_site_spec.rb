# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Ingestion::DiscoverRestaurantSite do
  let(:user) { create(:user) }
  def payload(response) = response.to_h[:structuredContent]
  def call(**args) = described_class.call(server_context: { user_id: user.id }, **args)

  it "returns fenced menu and location candidates from an allowed site" do
    stub_request(:get, "https://caracasgrillutah.com/").to_return(
      status: 200,
      headers: { "Content-Type" => "text/html" },
      body: <<~HTML
        <html><head>
          <script type="application/ld+json">
            {"@type":"Restaurant","name":"Caracas Grill","address":{"streetAddress":"1 Main"}}
          </script>
        </head><body><a href="/menu">Menu</a></body></html>
      HTML
    )

    response = call(url: "https://caracasgrillutah.com/")
    data = payload(response)

    expect(data[:menu_candidates].first[:url]).to eq("https://caracasgrillutah.com/menu")
    expect(data[:menu_candidates].first[:label]).to eq("<untrusted-content>Menu</untrusted-content>")
    expect(data[:location_candidates].first[:name]).to eq("<untrusted-content>Caracas Grill</untrusted-content>")
    expect(data[:next_step]).to include("start_menu_scan")
  end

  it "refuses DoorDash with a next_step that names own-site / paste / upload" do
    response = call(url: "https://www.doordash.com/store/caracas")
    data = payload(response)

    expect(response.to_h[:isError]).to be(true)
    expect(data[:error]).to eq("forbidden_host")
    expect(data[:next_step]).to include("own website")
    expect(data[:next_step]).to include("paste")
    expect(a_request(:get, /doordash/)).not_to have_been_made
  end

  it "refuses an anonymous caller" do
    response = described_class.call(server_context: {}, url: "https://example.com/")

    expect(payload(response)[:error]).to eq("unauthorized")
  end

  it "asks the user for addresses instead of looping on a locations page with none" do
    stub_request(:get, "https://ziataqueria.com/hours-locations").to_return(
      status: 200,
      headers: { "Content-Type" => "text/html" },
      body: <<~HTML
        <html><body>
          <a href="/hours-locations">Hours & Locations</a>
          <a href="/contact">Contact</a>
          <p>Come visit us.</p>
        </body></html>
      HTML
    )

    response = call(url: "https://ziataqueria.com/hours-locations")
    data = payload(response)

    expect(data[:location_candidates]).to eq([])
    expect(data[:next_step]).to include("Ask the user for the street address")
    expect(data[:next_step]).not_to include("Call discover_restaurant_site")
    expect(data[:next_step]).not_to include("hours-locations")
  end

  it "still points at a Locations page from the homepage when addresses are missing" do
    stub_request(:get, "https://ziataqueria.com/").to_return(
      status: 200,
      headers: { "Content-Type" => "text/html" },
      body: <<~HTML
        <html><body><a href="/hours-locations">Hours & Locations</a></body></html>
      HTML
    )

    data = payload(call(url: "https://ziataqueria.com/"))

    expect(data[:next_step]).to include("Call discover_restaurant_site")
    expect(data[:location_pages].first[:url]).to eq("https://ziataqueria.com/hours-locations")
  end

  it "does not tell the model to show menu URLs when none were found" do
    stub_request(:get, "https://serioustexasbbq.com/").to_return(
      status: 200,
      headers: { "Content-Type" => "text/html" },
      body: "<html><body><h1>Serious Texas</h1></body></html>"
    )
    stub_request(:get, "https://serioustexasbbq.com/robots.txt").to_return(
      status: 200, body: "User-agent: *\nDisallow: /\n"
    )

    data = payload(call(url: "https://serioustexasbbq.com/"))

    expect(data[:menu_candidates]).to eq([])
    expect(data[:location_candidates]).to eq([])
    expect(data[:next_step]).to include("menu page URL")
    expect(data[:next_step]).to include("pasted menu text")
    expect(data[:next_step]).not_to include("Show the user the menu URLs")
  end

  it "refuses a DoorDash white-label on a custom domain without parsing it" do
    stub_request(:get, "https://caracasgrillutah.com/").to_return(
      status: 200,
      headers: { "Content-Type" => "text/html" },
      body: <<~HTML
        <html><head>
          <script src="https://web-static.cdn4dd.com/storefront.js"></script>
          <script type="application/ld+json">
            {"@type":"Restaurant","name":"Should not be parsed","address":"1 Main"}
          </script>
        </head><body>Order pickup</body></html>
      HTML
    )

    response = call(url: "https://caracasgrillutah.com/")
    data = payload(response)

    expect(response.to_h[:isError]).to be(true)
    expect(data[:error]).to eq("forbidden_host")
    expect(data[:next_step]).to include("own website")
    expect(data[:location_candidates]).to be_nil
  end
end
