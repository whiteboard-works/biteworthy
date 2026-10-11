require "rails_helper"

# The chat never sees an upload's pixels, so this is how it learns an
# image's shape before choosing a crop for set_restaurant_branding — and,
# like that tool, it must not open another account's upload.
RSpec.describe Tools::Restaurants::InspectImage do
  let(:user) { create(:user) }

  def upload(bytes, by: user, content_type: "image/jpeg")
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(bytes), filename: "photo.jpg", content_type:,
      metadata: { "uploaded_by_user_id" => by.id }
    )
  end

  def payload(response) = response.to_h[:structuredContent]
  def call(id, as: user)
    described_class.call(server_context: { user_id: as.id }, attachment_id: id)
  end

  it "reports the size and what each branding slot would crop" do
    response = call(upload(ShapedImage.bytes(1000, 500)).signed_id)

    body = payload(response)
    expect(body).to include(width: 1000, height: 500, aspect_ratio: 2.0)
    expect(body.dig(:fits, :logo)).to include(
      target: { width: 400, height: 400, aspect: "1:1" },
      center_crop: { x: 250, y: 0, width: 500, height: 500 },
      trimmed: { horizontal: 0.5, vertical: 0.0 },
      smaller_than_target: false
    )
    expect(body.dig(:fits, :banner, :target)).to eq(width: 1600, height: 600, aspect: "8:3")
    expect(body.dig(:fits, :banner, :smaller_than_target)).to be(true)
  end

  it "reports the upright size of a photo the camera tagged as rotated" do
    rotated = Vips::Image.black(300, 100, bands: 3).copy
    rotated.set_type(GObject::GINT_TYPE, "orientation", 6)
    response = call(upload(rotated.write_to_buffer(".jpg")).signed_id)

    expect(payload(response)).to include(width: 100, height: 300)
  end

  # Branding would refuse it after the chat had planned a crop around it.
  it "says up front when an image is too many pixels to use" do
    response = call(upload(Vips::Image.black(8_001, 10, bands: 3).write_to_buffer(".png"), content_type: "image/png").signed_id)

    expect(payload(response)[:error]).to eq("invalid_argument")
  end

  it "does not open an upload another account made" do
    response = call(upload(ShapedImage.bytes(10, 10), by: create(:user)).signed_id)

    expect(payload(response)[:error]).to eq("invalid_argument")
  end

  it "refuses a file that is not an image" do
    response = call(upload("%PDF-1.4", content_type: "application/pdf").signed_id)

    expect(payload(response)[:error]).to eq("invalid_argument")
  end
end
