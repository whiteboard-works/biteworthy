require "rails_helper"

RSpec.describe Images::StripMetadata do
  def gps_fields(bytes)
    image = Vips::Image.new_from_buffer(bytes, "")
    image.get_fields.grep(/gps/i)
  end

  it "strips GPS EXIF so the stored bytes have no location metadata" do
    original = JpegWithGps.bytes
    expect(gps_fields(original)).not_to be_empty,
      "the fixture JPEG must carry GPS for this spec to mean anything"

    result = described_class.call(
      StringIO.new(original),
      filename: "phone.jpg",
      content_type: "image/jpeg"
    )
    stripped = result.io.read
    expect(gps_fields(stripped)).to be_empty
    expect(result.content_type).to eq("image/jpeg")
    expect(result.filename).to eq("phone.jpg")
  end

  it "raises Unprocessable on bytes that are not an image" do
    expect {
      described_class.call(StringIO.new("not an image"), filename: "x.jpg", content_type: "image/jpeg")
    }.to raise_error(Images::StripMetadata::Unprocessable)
  end
end
