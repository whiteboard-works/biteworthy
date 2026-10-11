require "rails_helper"

# The tool is the MCP door to Restaurants::Branding. What it must get
# right on its own: the ownership gate, and that an attachment id only
# resolves for the account that uploaded it.
RSpec.describe Tools::Restaurants::SetRestaurantBranding do
  let(:owner)      { create(:user) }
  let(:restaurant) { create(:restaurant, :published, claimed_by_user: owner, claimed_at: Time.current) }

  def upload_for(user, io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")))
    ActiveStorage::Blob.create_and_upload!(
      io:           io,
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

  describe "sizing" do
    let(:wide) { upload_for(owner, io: StringIO.new(ShapedImage.bytes(1000, 500, split: :horizontal))) }
    let(:tall) { upload_for(owner, io: StringIO.new(ShapedImage.bytes(800, 1200))) }

    def stored(attachment) = Vips::Image.new_from_buffer(attachment.download, "")

    # The model never sees the image, so the description is the only place
    # it learns what shape each slot wants.
    it "tells the model each slot's shape and size" do
      expect(described_class.description_value).to include("1:1", "400×400", "8:3", "1600×600")
    end

    it "center-crops an off-shape logo to a square and says what it did" do
      response = call(as: owner, restaurant: restaurant.slug, logo_attachment_id: wide.signed_id)

      logo = payload(response).dig(:adjustments, :logo)
      expect(logo[:source]).to eq(width: 1000, height: 500)
      expect(logo[:crop]).to eq(x: 250, y: 0, width: 500, height: 500)
      expect(logo[:stored]).to eq(width: 400, height: 400)
      expect(logo[:cropped]).to be(true)
      image = stored(restaurant.reload.logo)
      expect([ image.width, image.height ]).to eq([ 400, 400 ])
    end

    it "keeps the part of the banner the anchor names" do
      call(as: owner, restaurant: restaurant.slug, banner_attachment_id: tall.signed_id,
           banner_crop: { anchor: "top" })

      bytes = restaurant.reload.banner.download
      image = Vips::Image.new_from_buffer(bytes, "")
      expect([ image.width, image.height ]).to eq([ 800, 300 ])
      expect(ShapedImage.brightness(bytes)).to be > 240
    end

    it "takes an explicit crop box" do
      response = call(as: owner, restaurant: restaurant.slug, logo_attachment_id: wide.signed_id,
                      logo_crop: { x: 0, y: 0, w: 0.5, h: 1 })

      expect(payload(response).dig(:adjustments, :logo, :crop)).to eq(x: 0, y: 0, width: 500, height: 500)
      expect(ShapedImage.brightness(restaurant.reload.logo.download)).to be > 240
    end

    it "refuses a bad crop without touching the restaurant" do
      response = call(as: owner, restaurant: restaurant.slug, logo_attachment_id: wide.signed_id,
                      logo_crop: { x: 0.8, y: 0, w: 0.5, h: 1 })

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(restaurant.reload.logo).not_to be_attached
    end

    it "refuses a crop with no image to apply it to" do
      response = call(as: owner, restaurant: restaurant.slug, remove_logo: true, logo_crop: { anchor: "top" })

      expect(payload(response)[:error]).to eq("invalid_argument")
    end
  end
end
