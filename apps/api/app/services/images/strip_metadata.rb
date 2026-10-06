# frozen_string_literal: true

require "vips"

module Images
  # Rewrites an uploaded image through libvips with `strip: true` so the
  # bytes we store have no EXIF, IPTC, or XMP — including GPS. Phone
  # cameras embed a location; diner dish photos must not keep it.
  #
  # Autorotate runs first so a phone photo taken in portrait still
  # displays upright after the orientation tag is stripped. HEIC/HEIF
  # is decoded and written as JPEG: vips can read it, browsers cannot
  # always, and the admin dish-photo path already accepts JPEG.
  class StripMetadata
    class Unprocessable < StandardError; end

    JPEG_TYPES = %w[image/jpeg image/jpg].freeze
    PNG_TYPE   = "image/png"
    WEBP_TYPE  = "image/webp"
    HEIC_TYPES = %w[image/heic image/heif].freeze

    Result = Struct.new(:io, :filename, :content_type, keyword_init: true)

    def self.call(source, filename:, content_type:)
      new(source, filename:, content_type:).call
    end

    def initialize(source, filename:, content_type:)
      @source = source
      @filename = filename.to_s
      @content_type = content_type.to_s
    end

    def call
      image = Vips::Image.new_from_buffer(read_bytes, "")
      image = image.autorot
      ext, out_type, write_opts = write_format
      buffer = image.write_to_buffer(ext, **write_opts.merge(strip: true))
      Result.new(
        io: StringIO.new(buffer),
        filename: rewritten_filename(ext),
        content_type: out_type
      )
    rescue Vips::Error => e
      raise Unprocessable, "photo could not be processed (#{e.message})"
    end

    private

    def read_bytes
      if @source.respond_to?(:download)
        @source.download
      elsif @source.respond_to?(:tempfile)
        file = @source.tempfile
        file.rewind
        file.read
      elsif @source.respond_to?(:read)
        @source.rewind if @source.respond_to?(:rewind)
        @source.read
      else
        raise ArgumentError, "cannot read photo source #{@source.class}"
      end
    end

    def write_format
      case @content_type
      when PNG_TYPE
        [ ".png", PNG_TYPE, {} ]
      when WEBP_TYPE
        [ ".webp", WEBP_TYPE, { Q: 90 } ]
      else
        # JPEG, HEIC/HEIF, and anything else we accepted as an image:
        # store a stripped JPEG. HEIC in particular has no reliable
        # browser decode on the dish page.
        [ ".jpg", "image/jpeg", { Q: 90 } ]
      end
    end

    def rewritten_filename(ext)
      base = File.basename(@filename, ".*").presence || "dish"
      "#{base}#{ext}"
    end
  end
end
