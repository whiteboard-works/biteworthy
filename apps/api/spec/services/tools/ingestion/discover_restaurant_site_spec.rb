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
end
