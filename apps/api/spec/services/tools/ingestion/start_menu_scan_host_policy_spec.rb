# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Ingestion::StartMenuScan do
  let(:user) { create(:user) }
  let(:restaurant) { create(:restaurant, created_by_user_id: user.id) }

  def payload(response) = response.to_h[:structuredContent]

  it "refuses a DoorDash menu URL with a next_step naming own-site / paste / upload" do
    response = described_class.call(
      server_context: { user_id: user.id },
      restaurant: restaurant.slug,
      source_url: "https://www.doordash.com/store/caracas"
    )
    data = payload(response)

    expect(response.to_h[:isError]).to be(true)
    expect(data[:error]).to eq("forbidden_host")
    expect(data[:message]).to include("DoorDash")
    expect(data[:next_step]).to include("own website")
    expect(data[:next_step]).to include("upload")
    expect(a_request(:get, /doordash/)).not_to have_been_made
    expect(IngestionRun.where(restaurant: restaurant)).to be_empty
  end
end
