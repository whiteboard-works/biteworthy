# frozen_string_literal: true

require "mini_magick"

# Phase 4.11.1 — crop a per-dish photo out of a source menu page.
#
# Anthropic vision returns each dish's bounding box as normalized
# coordinates (`{x, y, w, h}`, all in 0..1, fractions of the source
# page) — see Phase 4.11.2's MenuExtractionSchema extension. This
# service takes the source blob + bbox and returns a cropped JPEG
# the IngestionItem#promote! step can attach to the resulting Item.
#
# Padding: bboxes from the model can be slightly off-center, so we
# pad the requested box by 5% in each direction (clamped to the
# source dimensions). Better to include a few extra pixels of
# whitespace than to slice the dish in half.
#
# Failure semantics: this service raises on bad input (nil bbox,
# non-numeric coordinates, blob that can't be opened). The caller
# (#promote!) wraps in a rescue so a single bad crop doesn't block
# the rest of an ingestion run from publishing.
module Ingestion
  class DishPhotoCropper
    DEFAULT_PADDING = 0.05  # 5%
    OUTPUT_QUALITY  = 85

    class InvalidBboxError < StandardError; end

    Cropped = Struct.new(:io, :width, :height, :content_type, keyword_init: true)

    class << self
      # Crop a source blob to the bbox + return the bytes as a Cropped
      # struct ready to attach via ActiveStorage.
      #
      # `source` must respond to `#download` (ActiveStorage::Blob does)
      # OR `#read` (raw IO). `bbox` is a Hash with string OR symbol
      # keys for x, y, w, h (each 0..1).
      def call(source:, bbox:, padding: DEFAULT_PADDING)
        bytes  = read_bytes(source)
        x, y, w, h = normalized_bbox!(bbox)

        image = MiniMagick::Image.read(bytes)
        src_w = image.width
        src_h = image.height

        # Convert normalized → pixel coords WITH padding, clamping at
        # the source edges so an over-eager pad doesn't slice off the
        # crop window.
        pad_x = padding * src_w
        pad_y = padding * src_h
        crop_x = (x * src_w - pad_x).clamp(0, src_w).floor
        crop_y = (y * src_h - pad_y).clamp(0, src_h).floor
        crop_w = (w * src_w + 2 * pad_x).clamp(1, src_w - crop_x).floor
        crop_h = (h * src_h + 2 * pad_y).clamp(1, src_h - crop_y).floor

        image.combine_options do |c|
          c.crop "#{crop_w}x#{crop_h}+#{crop_x}+#{crop_y}"
          c.repage.+
          c.quality OUTPUT_QUALITY.to_s
        end
        image.format "jpg"

        Cropped.new(
          io:           StringIO.new(image.to_blob).tap(&:rewind),
          width:        crop_w,
          height:       crop_h,
          content_type: "image/jpeg"
        )
      end

      private

      def read_bytes(source)
        if source.respond_to?(:download)
          source.download
        elsif source.respond_to?(:read)
          source.rewind if source.respond_to?(:rewind)
          source.read
        else
          source.to_s
        end
      end

      # Validate + extract the four floats. Accept symbol OR string
      # keys (jsonb columns roundtrip with string keys; in-Ruby callers
      # often use symbols).
      def normalized_bbox!(bbox)
        raise InvalidBboxError, "bbox must be a Hash, got #{bbox.class}" unless bbox.is_a?(Hash)
        x = bbox[:x] || bbox["x"]
        y = bbox[:y] || bbox["y"]
        w = bbox[:w] || bbox["w"]
        h = bbox[:h] || bbox["h"]

        [x, y, w, h].each_with_index do |v, i|
          raise InvalidBboxError, "bbox missing key #{%i[x y w h][i]}" if v.nil?
          raise InvalidBboxError, "bbox value not numeric: #{v.inspect}" unless v.is_a?(Numeric)
        end

        # Width + height must be positive; x + y must be in 0..1.
        raise InvalidBboxError, "bbox x out of [0,1]: #{x}" unless (0.0..1.0).cover?(x)
        raise InvalidBboxError, "bbox y out of [0,1]: #{y}" unless (0.0..1.0).cover?(y)
        raise InvalidBboxError, "bbox w must be > 0: #{w}" unless w.positive?
        raise InvalidBboxError, "bbox h must be > 0: #{h}" unless h.positive?

        [x.to_f, y.to_f, w.to_f, h.to_f]
      end
    end
  end
end
