# frozen_string_literal: true

module Images
  # The only path that attaches a user-supplied image (review or dish
  # submission photo, restaurant logo or banner). StripMetadata bounds
  # the raw bytes and dimensions, then rewrites the file without
  # EXIF/GPS, then attaches the rewritten IO. REST create/update and MCP
  # write_review/edit_review all go through here so a GPS-tagged phone
  # photo cannot land on a public blob. `name` picks the attachment;
  # restaurant branding passes `:logo` / `:banner`.
  module AttachPhoto
    module_function

    def call(record, source, filename: nil, content_type: nil, name: :photo)
      filename ||= identity(source).fetch(:filename)
      content_type ||= identity(source).fetch(:content_type)
      result = StripMetadata.call(source, filename:, content_type:)
      record.public_send(name).attach(
        io: result.io,
        filename: result.filename,
        content_type: result.content_type
      )
      result
    end

    def identity(source)
      if source.respond_to?(:original_filename)
        { filename: source.original_filename.presence || "photo.jpg",
          content_type: source.content_type.to_s }
      elsif source.respond_to?(:filename)
        { filename: source.filename.to_s.presence || "photo.jpg",
          content_type: source.content_type.to_s }
      else
        { filename: "photo.jpg", content_type: "image/jpeg" }
      end
    end
  end
end
