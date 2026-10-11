require "rails_helper"

# Logos render as a square and banners at 8:3 with CSS object-cover, so an
# off-shape upload used to be trimmed silently in the browser. Fit makes
# the stored image the served shape, and lets the caller pick which part
# survives — the chat cannot see the image, so it chooses by anchor or box.
RSpec.describe Images::Fit do
  def fit(bytes, size:, crop: nil)
    described_class.call(StringIO.new(bytes), content_type: "image/jpeg", size:, crop:)
  end

  def stored(result) = Vips::Image.new_from_buffer(result.io.read, "")

  describe ".plan" do
    it "center-crops a wide image to a square" do
      plan = described_class.plan(1000, 500, size: [ 400, 400 ])

      expect(plan.crop).to eq(x: 250, y: 0, width: 500, height: 500)
      expect(plan.stored).to eq(width: 400, height: 400)
      expect(plan.trimmed).to eq(horizontal: 0.5, vertical: 0.0)
    end

    it "keeps the top of a tall image with anchor top" do
      plan = described_class.plan(800, 1200, size: [ 1600, 600 ], crop: { anchor: "top" })

      expect(plan.crop).to eq(x: 0, y: 0, width: 800, height: 300)
    end

    it "keeps the right side with anchor right" do
      plan = described_class.plan(1000, 500, size: [ 400, 400 ], crop: { "anchor" => "right" })

      expect(plan.crop).to eq(x: 500, y: 0, width: 500, height: 500)
    end

    it "crops to a box first, then trims the box to the target shape" do
      plan = described_class.plan(1000, 1000, size: [ 400, 400 ],
                                  crop: { x: 0.1, y: 0.2, w: 0.6, h: 0.4 })

      expect(plan.crop).to eq(x: 200, y: 200, width: 400, height: 400)
    end

    it "never upscales a small image" do
      plan = described_class.plan(120, 120, size: [ 400, 400 ])

      expect(plan.stored).to eq(width: 120, height: 120)
      expect(plan.smaller_than_target).to be(true)
    end

    it "accepts box values from a multipart form as strings" do
      plan = described_class.plan(1000, 1000, size: [ 400, 400 ],
                                  crop: { "x" => "0", "y" => "0", "w" => "0.5", "h" => "0.5" })

      expect(plan.crop).to eq(x: 0, y: 0, width: 500, height: 500)
    end

    [
      [ "an unknown anchor", { anchor: "middle" } ],
      [ "a box outside the image", { x: 0.6, y: 0, w: 0.6, h: 1 } ],
      [ "a partial box", { x: 0.1, y: 0.1 } ],
      [ "a zero-size box", { x: 0, y: 0, w: 0, h: 1 } ],
      [ "a non-numeric box", { x: "left", y: 0, w: 1, h: 1 } ]
    ].each do |label, crop|
      it "refuses #{label}" do
        expect { described_class.plan(100, 100, size: [ 40, 40 ], crop:) }
          .to raise_error(Images::Fit::InvalidCrop) { |e| expect(e.code).to eq("invalid_crop") }
      end
    end
  end

  describe ".call" do
    it "stores a wide photo as a target-sized square" do
      result = fit(ShapedImage.bytes(1000, 500), size: [ 400, 400 ])
      image = stored(result)

      expect([ image.width, image.height ]).to eq([ 400, 400 ])
      expect(result.content_type).to eq("image/jpeg")
    end

    it "keeps the part the anchor names" do
      tall = ShapedImage.bytes(800, 1200) # top half white

      top    = fit(tall, size: [ 1600, 600 ], crop: { anchor: "top" })
      bottom = fit(tall, size: [ 1600, 600 ], crop: { anchor: "bottom" })

      expect(ShapedImage.brightness(top.io.read)).to be > 240
      expect(ShapedImage.brightness(bottom.io.read)).to be < 15
    end

    it "writes no metadata back" do
      result = fit(JpegWithGps.bytes, size: [ 8, 8 ])

      expect(stored(result).get_fields.grep(/gps/i)).to be_empty
    end
  end
end
