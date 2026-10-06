# frozen_string_literal: true

module DishPhotos
  # Makes an ActiveStorage blob look like the multipart upload
  # Admin::ItemEditor#handle_photo already knows (tempfile + filename +
  # content_type). Approving a diner photo must go through that path so
  # the card/thumb/full WebP variants generate the same way a staff
  # PATCH does.
  class UploadedBlob
    attr_reader :original_filename, :content_type

    def initialize(blob)
      @original_filename = blob.filename.to_s
      @content_type = blob.content_type
      @bytes = blob.download
    end

    def tempfile
      @tempfile ||= begin
        ext = File.extname(@original_filename).presence || ".jpg"
        file = Tempfile.new([ "dish-photo", ext ])
        file.binmode
        file.write(@bytes)
        file.rewind
        file
      end
    end

    def close
      return if @tempfile.nil? || @tempfile.closed?

      @tempfile.close
      @tempfile.unlink
    end
  end
end
