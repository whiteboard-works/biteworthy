# frozen_string_literal: true

require "vips"

module Images
  # Rewrites an uploaded image through libvips with `strip: true` so the
  # bytes we store have no EXIF, IPTC, or XMP — including GPS. Phone
  # cameras embed a location; diner photos (reviews and dish submissions)
  # must not keep it.
  #
  # Bounds run *before* a full decode: raw byte size, then width/height
  # from a sequential header read. A huge compressed image must not be
  # able to exhaust memory by expanding inside write_to_buffer.
  #
  # Autorotate runs so a phone photo taken in portrait still displays
  # upright after the orientation tag is stripped. HEIC/HEIF is decoded
  # and written as JPEG: vips can read it, browsers cannot always.
  class StripMetadata
    class Unprocessable < StandardError
      attr_reader :code

      def initialize(message, code: "unprocessable_image")
        super(message)
        @code = code
      end
    end

    class TooLarge < Unprocessable
      def initialize(message = "photo must be 5 MB or smaller")
        super(message, code: "too_large")
      end
    end

    class TooManyPixels < Unprocessable
      def initialize(message = "photo is too many pixels — try a smaller image")
        super(message, code: "too_many_pixels")
      end
    end

    JPEG_TYPES = %w[image/jpeg image/jpg].freeze
    PNG_TYPE   = "image/png"
    WEBP_TYPE  = "image/webp"
    HEIC_TYPES = %w[image/heic image/heif].freeze
    MAX_EDGE   = 8_000
    MAX_PIXELS = 40_000_000

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
      raise TooLarge if source_byte_size > HasPhotoValidation::MAX_PHOTO_BYTES
      unless allowed_type?
        raise Unprocessable.new(
          "photo must be one of #{HasPhotoValidation::ALLOWED_PHOTO_TYPES.join(', ')}",
          code: "unsupported_type"
        )
      end

      with_source_path do |path|
        header = open_image(path, access: :sequential)
        check_dimensions!(header)
        image = open_image(path)
        image = image.autorot
        ext, out_type, write_opts = write_format
        buffer = image.write_to_buffer(ext, **write_opts.merge(strip: true))
        Result.new(
          io: StringIO.new(buffer),
          filename: generated_filename(ext),
          content_type: out_type
        )
      end
    rescue TooLarge, TooManyPixels
      raise
    rescue Unprocessable
      raise
    rescue Vips::Error
      raise Unprocessable, "We could not read that image. Try a JPEG or PNG photo."
    end

    private

    def allowed_type?
      HasPhotoValidation::ALLOWED_PHOTO_TYPES.include?(@content_type)
    end

    def source_byte_size
      file = if @source.respond_to?(:tempfile)
        @source.tempfile
      elsif @source.respond_to?(:byte_size)
        return @source.byte_size
      else
        @source
      end

      return file.size if file.respond_to?(:size)

      read_bytes.bytesize
    end

    def check_dimensions!(image)
      width = image.width
      height = image.height
      if width > MAX_EDGE || height > MAX_EDGE || (width * height) > MAX_PIXELS
        raise TooManyPixels
      end
    end

    # `:truncated` still rejects corrupt/cut-off files. `:error` is too
    # strict: phone JPEGs with quirky progressive scans fail even though
    # they decode and display fine.
    def open_image(path, access: nil)
      opts = { fail_on: :truncated }
      opts[:access] = access if access
      Vips::Image.new_from_file(path, **opts)
    end

    def with_source_path
      existing = existing_path
      if existing
        yield existing
      else
        Tempfile.create([ "upload", ".img" ]) do |tmp|
          tmp.binmode
          tmp.write(read_bytes)
          tmp.flush
          yield tmp.path
        end
      end
    end

    def existing_path
      file = @source.respond_to?(:tempfile) ? @source.tempfile : @source
      return unless file.respond_to?(:path)

      path = file.path
      path if path.present? && File.exist?(path)
    end

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
        [ ".jpg", "image/jpeg", { Q: 90 } ]
      end
    end

    def generated_filename(ext)
      "#{SecureRandom.uuid}#{ext}"
    end
  end
end
