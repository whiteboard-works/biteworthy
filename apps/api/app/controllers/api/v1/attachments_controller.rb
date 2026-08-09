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
    class AttachmentsController < BaseController
      def create
        file = params[:file]
        return render_error("Attach a file.") unless file.respond_to?(:tempfile)
        return render_error("That file is too large.") if file.size.to_i > max_bytes

        blob = store(file)
        # Declared content types lie; ActiveStorage sniffs the real one on
        # create, so the check that matters happens after the write.
        unless allowed?(blob.content_type)
          blob.purge
          return render_error("Only JPEG, PNG, HEIC, WebP, and PDF files can be scanned.")
        end

        render json: serialize(blob), status: :created
      end

      private

      def store(file)
        ActiveStorage::Blob.create_and_upload!(
          io:           file.tempfile,
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

      def render_error(message)
        render json: { error: message }, status: :unprocessable_entity
      end
    end
  end
end
