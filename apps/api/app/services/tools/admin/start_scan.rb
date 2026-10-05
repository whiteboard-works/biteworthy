# frozen_string_literal: true

module Tools
  module Admin
    # Start a menu scan with more input options than the regular user tool.
    # Accepts base64-encoded content and raw source text, not only URLs and
    # signed blob ids, so captcha-blocked or manual-entry menus can still be
    # ingested.
    class StartScan < Tools::AdminBase
      tool_name "start_scan"
      title "Scan a menu (admin)"
      description <<~TEXT
        Start extracting a restaurant's menu from a URL, raw text, an uploaded
        photo/PDF, OR base64-encoded content. Provide exactly one source.

        This is the admin version of start_menu_scan: it accepts base64_pdf
        and base64_image for captcha-blocked or manually-supplied menus that
        cannot be fetched by URL, plus source_text for pasted/typed menu
        content. The base64 content is decoded and processed the same way as
        an uploaded file.

        Returns immediately — extraction takes 20-60 seconds. Poll get_scan
        with the returned scan_id.
      TEXT

      input_schema(
        properties: {
          restaurant: {
            type: "string",
            description: "Restaurant UUID or slug."
          },
          source_url: {
            type: "string",
            description: "URL of a menu page or PDF to fetch."
          },
          source_text: {
            type: "string",
            description: "Raw menu text."
          },
          attachment_ids: {
            type: "array",
            items: { type: "string" },
            description: "Signed blob ids from a prior upload."
          },
          base64_pdf: {
            type: "string",
            description: "Base64-encoded PDF file content. Decoded and processed as a PDF attachment."
          },
          base64_image: {
            type: "string",
            description: "Base64-encoded image (JPEG/PNG/WebP/HEIC). Decoded and processed as an image attachment."
          }
        },
        required: [ "restaurant" ]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      running_description { "Starting menu scan" }

      ERROR_MESSAGES = Tools::Ingestion::StartMenuScan::ERROR_MESSAGES.merge(
        multiple_sources: "Provide exactly one of source_url, source_text, attachment_ids, base64_pdf, or base64_image.",
        base64_decode_failed: "The base64 content could not be decoded."
      ).freeze

      def self.perform(context:, restaurant:, source_url: nil, source_text: nil, attachment_ids: nil,
                       base64_pdf: nil, base64_image: nil)
        context.admin!
        user = context.user
        record = Restaurant.kept.find_by_id_or_slug!(restaurant)

        sources = [ source_url, source_text, attachment_ids, base64_pdf, base64_image ].compact
        return error(ERROR_MESSAGES[:multiple_sources], code: "multiple_sources") if sources.size > 1

        files = resolve_files(user, attachment_ids, base64_pdf, base64_image)

        result = ::Ingestion::StartRun.call(
          user: user,
          restaurant: record,
          files: files,
          source_url: source_url,
          source_text: source_text
        )

        return failure(result) unless result.ok?

        run = result.run
        ok(
          scan_id: run.id,
          restaurant: { id: record.id, slug: record.slug, name: record.name },
          status: run.status,
          ready: false,
          next_step: "Poll get_scan with this scan_id."
        )
      rescue Errors::InvalidArgument => e
        error(e.message, code: "base64_decode_failed")
      end

      def self.failure(result)
        message = ERROR_MESSAGES.fetch(result.error, "Could not start the scan.")
        detail = result.detail.presence
        error([ message, detail&.to_json ].compact.join(" "), code: result.error.to_s)
      end
      private_class_method :failure

      # Resolve attachment_ids like the user tool does, plus decode base64
      # content and create temporary blobs for it.
      def self.resolve_files(user, attachment_ids, base64_pdf, base64_image)
        files = []

        # Signed blob ids
        if attachment_ids.present?
          files += Array(attachment_ids).map(&:to_s).reject(&:blank?).filter_map do |id|
            blob = ActiveStorage::Blob.find_signed(id)
            blob if blob && blob.metadata["uploaded_by_user_id"].to_s == user.id.to_s
          end
        end

        # Base64 PDF
        if base64_pdf.present?
          files << decode_base64_blob(base64_pdf, "application/pdf", "menu.pdf")
        end

        # Base64 image
        if base64_image.present?
          # StartRun will validate content type; default to JPEG
          files << decode_base64_blob(base64_image, "image/jpeg", "menu.jpg")
        end

        files
      end
      private_class_method :resolve_files

      def self.decode_base64_blob(base64_string, content_type, filename)
        content = Base64.strict_decode64(base64_string)
        io = StringIO.new(content)
        io.set_encoding(Encoding::BINARY)

        # Create a temporary blob for StartRun to process
        blob = ActiveStorage::Blob.create_and_upload!(
          io: io,
          filename: filename,
          content_type: content_type
        )
        blob
      rescue ArgumentError => e
        raise Errors::InvalidArgument, ERROR_MESSAGES[:base64_decode_failed]
      end
      private_class_method :decode_base64_blob
    end
  end
end
