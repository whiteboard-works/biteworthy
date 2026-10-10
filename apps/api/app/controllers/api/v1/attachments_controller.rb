module Api
  module V1
    # Uploads a menu photo or PDF and hands back an id.
    #
    # This exists so bytes never enter the agent's context. The chat sends
    # the id; `start_menu_scan` resolves it to a blob and the vision call
    # happens inside the tool, where injected text in a photo has no tools
    # to reach.
    #
    # The returned id is a **signed** id: unguessable, and the blob also
    # records who uploaded it, so one account cannot scan another's upload
    # by walking the sequential primary keys.
    #
    # Two credentials open `create`: the session JWT (mobile, MCP clients)
    # and a ticket from `#ticket` for the browser, which holds its JWT in
    # an HttpOnly cookie it cannot send here (Attachments::UploadTicket).
    class AttachmentsController < BaseController
      TICKET_HEADER = "X-Upload-Ticket".freeze

      # Raw bytes accepted at the door before any shrinking. Both clients
      # resize a photo before sending it, so an image over the per-file
      # limit is refused as before; a PDF between the limit and this
      # ceiling gets one Ghostscript pass (Pdfs::Shrink) first. The same
      # 15 MB as Images::StripMetadata's raw guard, so "how big a file can
      # I send" has one answer.
      MAX_RAW_BYTES = 15 * 1024 * 1024

      skip_before_action :authenticate_user!, only: :create
      before_action :authenticate_uploader!, only: :create

      def create
        file = params[:file]
        return render_error("Attach a file.") unless file.respond_to?(:tempfile)
        return render_error("That file is too large.") if file.size.to_i > raw_ceiling

        io = file.tempfile
        if file.size.to_i > max_bytes
          io = pdf?(file) ? Pdfs::Shrink.call(file.tempfile.path) : nil
          return render_error("That file is too large.") if io.nil? || io.size > max_bytes
        end

        blob = store(io, file)
        io.close! if io != file.tempfile
        # Declared content types lie; ActiveStorage sniffs the real one on
        # create, so the check that matters happens after the write.
        unless allowed?(blob.content_type)
          blob.purge
          return render_error("Only JPEG, PNG, HEIC, WebP, and PDF files can be scanned.")
        end

        render json: serialize(blob), status: :created
      end

      # A ticket the browser carries to `create`. Minted with the session,
      # so this action keeps the JWT requirement the rest of the API has.
      # `max_bytes` is this caller's raw ceiling, so the client refuses a
      # bigger file before sending it rather than after.
      def ticket
        render json: {
          ticket:     Attachments::UploadTicket.issue(current_user),
          expires_at: Attachments::UploadTicket::TTL.from_now.iso8601,
          max_bytes:  raw_ceiling
        }, status: :created
      end

      private

      def authenticate_uploader!
        ticket = request.headers[TICKET_HEADER]
        return authenticate_user! if ticket.blank?

        @ticket_user = Attachments::UploadTicket.user_for(ticket)
        return if @ticket_user

        render json: { error: "That upload ticket is not valid." }, status: :unauthorized
      end

      def current_user
        @ticket_user || super
      end

      def store(io, file)
        ActiveStorage::Blob.create_and_upload!(
          io:           io,
          filename:     file.original_filename.presence || "upload",
          content_type: file.content_type.presence,
          metadata:     { "uploaded_by_user_id" => current_user.id }
        )
      end

      def serialize(blob)
        {
          id:           blob.signed_id,
          filename:     blob.filename.to_s,
          content_type: blob.content_type,
          byte_size:    blob.byte_size
        }
      end

      def allowed?(content_type)
        ::Ingestion::StartRun::ALLOWED_INPUT_CONTENT_TYPES.include?(content_type.to_s)
      end

      # Sniffed, not declared, for the same reason the post-store check
      # is: whether a file gets the Ghostscript pass must not depend on
      # what the client called it.
      def pdf?(file)
        Marcel::MimeType.for(file.tempfile, name: file.original_filename.to_s) == "application/pdf"
      ensure
        file.tempfile.rewind
      end

      # Same ceiling the scan itself enforces — rejecting at upload gives
      # the user the error immediately instead of after they hit send.
      # Asked of `StartRun` rather than recomputed here, because the two
      # had already drifted: this door read the raw env value and knew
      # nothing about the super tier, so that tier's per-file headroom was
      # unreachable through the only door the chat uses.
      #
      # Known gap, deliberately not closed here: uploads arrive one POST
      # at a time with no batch identity, so this door cannot enforce the
      # *aggregate* ceiling — three individually-legal 8 MB photos are
      # stored and only refused at scan time. Inventing a batch id to fix
      # that costs more than it saves while `PurgeUnscannedAttachmentsJob`
      # already reclaims blobs nobody scanned.
      def max_bytes
        ::Ingestion::StartRun.per_file_byte_limit(current_user)
      end

      # The super tier's per-file limit can sit above MAX_RAW_BYTES; the
      # ceiling never undercuts what the scan would accept.
      def raw_ceiling
        [ MAX_RAW_BYTES, max_bytes ].max
      end

      def render_error(message)
        render json: { error: message }, status: :unprocessable_entity
      end
    end
  end
end
