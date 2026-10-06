require "rails_helper"
require "zlib"

RSpec.describe Images::StripMetadata do
  def gps_fields(bytes)
    image = Vips::Image.new_from_buffer(bytes, "")
    image.get_fields.grep(/gps/i)
  end

  # Valid PNG container with the given IHDR size. Sequential header
  # reads pick up width/height without decoding pixel data, so this
  # stays tiny even at 12000×12000.
  def png_with_dimensions(width, height)
    ihdr = [ width, height, 8, 0, 0, 0, 0 ].pack("N2C5")
    deflate = Zlib::Deflate.deflate("\0")
    "\x89PNG\r\n\x1A\n".b + png_chunk("IHDR", ihdr) +
      png_chunk("IDAT", deflate) + png_chunk("IEND", "".b)
  end

  def png_chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
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
    expect(result.filename).to match(/\A[0-9a-f-]{36}\.jpg\z/)
  end

  it "rejects a file over 5 MB before decoding it" do
    big = StringIO.new("x" * (HasPhotoValidation::MAX_PHOTO_BYTES + 1))
    expect {
      described_class.call(big, filename: "huge.jpg", content_type: "image/jpeg")
    }.to raise_error(Images::StripMetadata::TooLarge)
  end

  it "rejects a huge-dimension image from the header without accepting it" do
    file = Tempfile.new([ "huge", ".png" ])
    file.binmode
    file.write(png_with_dimensions(12_000, 12_000))
    file.flush
    expect(File.size(file.path)).to be < HasPhotoValidation::MAX_PHOTO_BYTES

    upload = Rack::Test::UploadedFile.new(file.path, "image/png")
    expect {
      described_class.call(upload, filename: "huge.png", content_type: "image/png")
    }.to raise_error(Images::StripMetadata::TooManyPixels)
  ensure
    file&.close!
  end

  it "raises Unprocessable on bytes that are not an image" do
    tmp = Tempfile.new([ "x", ".jpg" ])
    tmp.binmode
    tmp.write("not an image")
    tmp.flush
    expect {
      described_class.call(tmp, filename: "x.jpg", content_type: "image/jpeg")
    }.to raise_error(Images::StripMetadata::Unprocessable)
  ensure
    tmp&.close!
  end
end
