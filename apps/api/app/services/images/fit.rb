# frozen_string_literal: true

require "vips"

module Images
  # Crops an image to a target shape and shrinks it to at most the target
  # size. Logos and banners are served at a fixed shape (CSS object-cover
  # used to trim anything else silently), so the stored copy is made that
  # shape here, and the caller picks which part survives.
  #
  # The chat never sees pixels, so a crop is numeric: an `anchor` (which
  # edge to keep when trimming to shape) and/or a box `x, y, w, h` in
  # fractions of the image. A box is cut first, then trimmed to shape
  # around the anchor (default center). Never upscales.
  #
  # Expects an already-stripped, upright image (Images::StripMetadata
  # runs first); writes with `strip: true` regardless.
  class Fit
    class InvalidCrop < StripMetadata::Unprocessable
      def initialize(message)
        super(message, code: "invalid_crop")
      end
    end

    ANCHORS = %w[center top bottom left right].freeze
    BOX_KEYS = %w[x y w h].freeze

    Plan = Struct.new(:source, :crop, :stored, :trimmed, :smaller_than_target, keyword_init: true)
    Result = Struct.new(:io, :content_type, :source, :crop, :stored, keyword_init: true) do
      def cropped? = crop[:width] != source[:width] || crop[:height] != source[:height]
    end

    WRITE_FORMATS = { "image/png" => [ ".png", {} ], "image/webp" => [ ".webp", { Q: 90 } ] }.freeze

    class << self
      def call(source, content_type:, size:, crop: nil)
        image = Vips::Image.new_from_buffer(read(source), "")
        plan = plan(image.width, image.height, size:, crop:)
        box = plan.crop
        image = image.crop(box[:x], box[:y], box[:width], box[:height])
        if plan.stored[:width] < box[:width]
          image = image.resize(plan.stored[:width].fdiv(box[:width]), vscale: plan.stored[:height].fdiv(box[:height]))
        end

        ext, opts = WRITE_FORMATS.fetch(content_type, [ ".jpg", { Q: 90 } ])
        Result.new(
          io:           StringIO.new(image.write_to_buffer(ext, strip: true, **opts)),
          content_type: WRITE_FORMATS.key?(content_type) ? content_type : "image/jpeg",
          source:       plan.source,
          crop:         box,
          stored:       { width: image.width, height: image.height }
        )
      end

      # Pure arithmetic, so `inspect_image` can say what a crop would do
      # without writing anything. Pixel boxes are in source coordinates.
      def plan(src_w, src_h, size:, crop: nil)
        anchor, box = normalize(crop)
        bx, by, bw, bh = pixel_box(box, src_w, src_h)

        target_w, target_h = size
        ratio = target_w.fdiv(target_h)
        if bw.fdiv(bh) > ratio
          cw, ch = (bh * ratio).round.clamp(1, bw), bh
        else
          cw, ch = bw, (bw / ratio).round.clamp(1, bh)
        end
        cx = bx + offset(bw - cw, anchor, "left", "right")
        cy = by + offset(bh - ch, anchor, "top", "bottom")

        scale = [ target_w.fdiv(cw), target_h.fdiv(ch), 1.0 ].min
        Plan.new(
          source:              { width: src_w, height: src_h },
          crop:                { x: cx, y: cy, width: cw, height: ch },
          stored:              { width: (cw * scale).round.clamp(1, target_w), height: (ch * scale).round.clamp(1, target_h) },
          trimmed:             { horizontal: (1 - cw.fdiv(src_w)).round(2), vertical: (1 - ch.fdiv(src_h)).round(2) },
          smaller_than_target: scale == 1.0 && (cw < target_w || ch < target_h)
        )
      end

      private

      def normalize(crop)
        crop = (crop || {}).to_h.transform_keys(&:to_s).compact_blank
        anchor = crop.fetch("anchor", "center").to_s
        raise InvalidCrop, "anchor must be one of #{ANCHORS.join(', ')}" unless anchor.in?(ANCHORS)

        given = BOX_KEYS & crop.keys
        return [ anchor, nil ] if given.empty?
        raise InvalidCrop, "a crop box needs all of x, y, w, h" unless given.size == BOX_KEYS.size

        x, y, w, h = BOX_KEYS.map { |key| number(crop[key]) }
        unless x >= 0 && y >= 0 && w.positive? && h.positive? && x + w <= 1.001 && y + h <= 1.001
          raise InvalidCrop, "a crop box is fractions of the image: x, y >= 0, w, h > 0, x + w and y + h <= 1"
        end

        [ anchor, [ x, y, w, h ] ]
      end

      def number(value)
        Float(value)
      rescue ArgumentError, TypeError
        raise InvalidCrop, "crop box values must be numbers between 0 and 1"
      end

      def pixel_box(box, src_w, src_h)
        return [ 0, 0, src_w, src_h ] unless box

        x, y, w, h = box
        px = (x * src_w).round.clamp(0, src_w - 1)
        py = (y * src_h).round.clamp(0, src_h - 1)
        [ px, py, (w * src_w).round.clamp(1, src_w - px), (h * src_h).round.clamp(1, src_h - py) ]
      end

      def offset(slack, anchor, start_edge, end_edge)
        case anchor
        when start_edge then 0
        when end_edge then slack
        else slack / 2
        end
      end

      def read(source)
        source.rewind if source.respond_to?(:rewind)
        source.read
      end
    end
  end
end
