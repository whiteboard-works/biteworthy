require "rails_helper"

# The tool is the MCP door to Restaurants::Branding. What it must get
# right on its own: the ownership gate, and that an attachment id only
# resolves for the account that uploaded it.
RSpec.describe Tools::Restaurants::SetRestaurantBranding do
  let(:owner)      { create(:user) }
  let(:restaurant) { create(:restaurant, :published, claimed_by_user: owner, claimed_at: Time.current) }

  def upload_for(user)
    ActiveStorage::Blob.create_and_upload!(
      io:           File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")),
      filename:     "logo.jpg",
      content_type: "image/jpeg",
      metadata:     { "uploaded_by_user_id" => user.id }
    )
  end

  def payload(response) = response.to_h[:structuredContent]
  def call(as:, **args)
    described_class.call(server_context: { user_id: as.id, public_host: "https://biteworthy.test" }, **args)
  end

  it "attaches the owner's uploaded logo" do
    response = call(as: owner, restaurant: restaurant.slug, logo_attachment_id: upload_for(owner).signed_id)

    expect(payload(response)[:logo_url]).to be_present
    expect(payload(response)[:banner_url]).to be_nil
    expect(restaurant.reload.logo).to be_attached
  end

  it "lets an admin set the banner" do
    admin = create(:user, :admin)
    response = call(as: admin, restaurant: restaurant.id, banner_attachment_id: upload_for(admin).signed_id)

    expect(payload(response)[:banner_url]).to be_present
    expect(restaurant.reload.banner).to be_attached
  end

  it "refuses a user who is not the verified owner" do
    stranger = create(:user)
    response = call(as: stranger, restaurant: restaurant.slug, logo_attachment_id: upload_for(stranger).signed_id)

    expect(payload(response)[:error]).to eq("forbidden")
    expect(restaurant.reload.logo).not_to be_attached
  end

  it "does not resolve an attachment somebody else uploaded" do
    response = call(as: owner, restaurant: restaurant.slug, logo_attachment_id: upload_for(create(:user)).signed_id)

    expect(payload(response)[:error]).to eq("invalid_argument")
    expect(restaurant.reload.logo).not_to be_attached
  end

  it "removes a logo with the flag" do
    call(as: owner, restaurant: restaurant.slug, logo_attachment_id: upload_for(owner).signed_id)

    response = call(as: owner, restaurant: restaurant.slug, remove_logo: true)

    expect(payload(response)[:logo_url]).to be_nil
    expect(restaurant.reload.logo).not_to be_attached
  end

  it "asks for something to change when given nothing" do
    response = call(as: owner, restaurant: restaurant.slug)

    expect(payload(response)[:error]).to eq("invalid_argument")
  end
end
