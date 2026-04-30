require "rails_helper"
require "mini_magick"

RSpec.describe Ingestion::DishPhotoCropper do
  # The committed JPEG fixture from the cassette PR (4.11.0). Real
  # menu page so spec output is interpretable. Keep `let!` lazy-eval —
  # we don't need to load it for the validation specs.
  let(:menu_path)   { Rails.root.join("spec/fixtures/menus/sample.jpg") }
  let(:menu_blob)   { File.open(menu_path, "rb") }
  let(:source_dims) do
    img = MiniMagick::Image.open(menu_path)
    [img.width, img.height]
  end

  describe ".call" do
    it "returns a Cropped struct carrying JPEG bytes + dimensions" do
      out = described_class.call(
        source: menu_blob,
        bbox:   { x: 0.5, y: 0.05, w: 0.45, h: 0.2 },
        padding: 0
      )
      expect(out.content_type).to eq("image/jpeg")
      expect(out.width).to be > 0
      expect(out.height).to be > 0
      expect(out.io).to be_a(StringIO)

      # Round-trip through MiniMagick to confirm the bytes are a real
      # decodable JPEG (not garbage from a failed combine_options).
      decoded = MiniMagick::Image.read(out.io)
      expect(decoded.width).to eq(out.width)
      expect(decoded.height).to eq(out.height)
    end

    it "accepts string-key bboxes (jsonb roundtrip)" do
      expect {
        described_class.call(source: menu_blob, bbox: { "x" => 0.1, "y" => 0.1, "w" => 0.2, "h" => 0.2 })
      }.not_to raise_error
    end

    it "pads the requested box by 5% by default" do
      sw, sh = source_dims
      no_pad = described_class.call(source: menu_blob, bbox: { x: 0.4, y: 0.4, w: 0.2, h: 0.2 }, padding: 0)
      with_pad = described_class.call(source: menu_blob, bbox: { x: 0.4, y: 0.4, w: 0.2, h: 0.2 })
      # Padded crop should be larger by ~10% of source dims in each
      # direction (5% pad on each side).
      expect(with_pad.width  - no_pad.width).to  be_within(2).of((0.10 * sw).round)
      expect(with_pad.height - no_pad.height).to be_within(2).of((0.10 * sh).round)
    end

    it "clamps padding so a near-edge bbox doesn't slice off" do
      out = described_class.call(
        source: menu_blob,
        bbox:   { x: 0.0, y: 0.0, w: 0.1, h: 0.1 },
        padding: 0.2
      )
      sw, sh = source_dims
      # crop_x and crop_y get clamped to 0 when padding pushes them
      # negative. Width/height should still be sensible.
      expect(out.width).to  be > 0
      expect(out.height).to be > 0
      expect(out.width).to  be < sw
      expect(out.height).to be < sh
    end

    it "raises on a missing key" do
      expect {
        described_class.call(source: menu_blob, bbox: { x: 0.1, y: 0.1, w: 0.1 })
      }.to raise_error(Ingestion::DishPhotoCropper::InvalidBboxError, /missing key h/)
    end

    it "raises on a non-numeric value" do
      expect {
        described_class.call(source: menu_blob, bbox: { x: "left", y: 0.1, w: 0.1, h: 0.1 })
      }.to raise_error(Ingestion::DishPhotoCropper::InvalidBboxError, /not numeric/)
    end

    it "raises on out-of-range x" do
      expect {
        described_class.call(source: menu_blob, bbox: { x: 1.5, y: 0.1, w: 0.1, h: 0.1 })
      }.to raise_error(Ingestion::DishPhotoCropper::InvalidBboxError, /out of \[0,1\]/)
    end

    it "raises on zero width" do
      expect {
        described_class.call(source: menu_blob, bbox: { x: 0.1, y: 0.1, w: 0, h: 0.1 })
      }.to raise_error(Ingestion::DishPhotoCropper::InvalidBboxError, /w must be > 0/)
    end

    it "raises when bbox isn't a Hash" do
      expect {
        described_class.call(source: menu_blob, bbox: [0.1, 0.1, 0.1, 0.1])
      }.to raise_error(Ingestion::DishPhotoCropper::InvalidBboxError, /must be a Hash/)
    end

    it "works with an ActiveStorage::Blob-shaped source (responds to #download)" do
      blob_double = double("blob", download: File.binread(menu_path))
      expect {
        described_class.call(source: blob_double, bbox: { x: 0.1, y: 0.1, w: 0.2, h: 0.2 })
      }.not_to raise_error
    end
  end
end
