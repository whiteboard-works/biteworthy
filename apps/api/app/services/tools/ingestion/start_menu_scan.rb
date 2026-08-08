# frozen_string_literal: true

module Tools
  module Ingestion
    # Kick off a menu scan. Returns immediately — extraction is a
    # tens-of-seconds vision call and blocking a tool call on it would time
    # out most clients. Poll `get_scan_status` and read the dishes with
    # `list_staged_items` once it reports ready.
    class StartMenuScan < Tools::Ingestion::Base
      tool_name "start_menu_scan"
      title "Scan a menu"
      description <<~TEXT
        Start extracting a restaurant's menu from a URL, pasted text, or an
        uploaded photo/PDF. Provide exactly one source.

        This returns as soon as the scan is queued — it does NOT wait for the
        result. Extraction takes roughly 20-60 seconds. Poll `get_scan_status`
        with the returned scan_id, then call `list_staged_items` once it
        reports `ready: true`.

        Nothing reaches the live menu from this call. Everything lands in a
        staging area for review, and only `accept_staged_items` publishes.

        Scans are quota-limited per user per day and bounded by a global
        spend ceiling; you will get a clear error if either is hit.
      TEXT

      input_schema(
        properties: {
          restaurant: {
            type: "string",
            description: "Restaurant UUID or slug to scan. Use search_restaurants to find it."
          },
          source_url: {
            type: "string",
            description: "URL of a menu page or PDF to fetch and read."
          },
          source_text: {
            type: "string",
            description: "Raw menu text pasted by the user."
          },
          attachment_ids: {
            type: "array",
            items: { type: "string" },
            description: "Ids returned when the user uploaded photos or PDFs through the app. " \
                         "You cannot invent these — if the user has not uploaded anything, ask them to."
          }
        },
        required: ["restaurant"]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      # Wording matters here: the model relays these to a user who needs to
      # know whether to wait, fix something, or give up.
      ERROR_MESSAGES = {
        forbidden_restaurant: "You can only scan restaurants that are published, or drafts you created yourself.",
        no_inputs:            "Provide one of source_url, source_text, or attachment_ids.",
        url_fetch_failed:     "That URL could not be fetched.",
        quota_exceeded:       "Daily scan limit reached for this account. Try again tomorrow.",
        cost_ceiling_reached: "Scanning is paused — the service hit its daily processing budget. Try again tomorrow.",
        too_many_files:       "Too many files in one scan.",
        file_too_large:       "One of those files is too large.",
        unsupported_file_type: "Only JPEG, PNG, HEIC, WebP, and PDF files can be scanned.",
        text_too_large:       "That menu text is too long to scan in one go."
      }.freeze

      def self.perform(context:, restaurant:, source_url: nil, source_text: nil, attachment_ids: nil)
        user   = context.user!
        record = Restaurant.find_by_id_or_slug!(restaurant)

        result = ::Ingestion::StartRun.call(
          user:        user,
          restaurant:  record,
          files:       resolve_attachments(attachment_ids, user),
          source_url:  source_url,
          source_text: source_text
        )

        return failure(result) unless result.ok?

        run = result.run
        ok(
          scan_id:    run.id,
          restaurant: { id: record.id, slug: record.slug, name: record.name },
          status:     run.status,
          ready:      false,
          next_step:  "Poll get_scan_status with this scan_id; extraction usually takes 20-60 seconds."
        )
      end

      def self.failure(result)
        message = ERROR_MESSAGES.fetch(result.error, "Could not start the scan.")
        detail  = result.detail.presence
        error([message, detail&.to_json].compact.join(" "), code: result.error.to_s)
      end
      private_class_method :failure

      # Blobs the user uploaded through the app. Ids that don't resolve, or
      # that belong to someone else, are dropped rather than raising —
      # StartRun's no_inputs guard then gives the model a clearer message
      # than "blob not found" would.
      #
      # Blob primary keys are sequential integers, so accepting a raw id
      # would let any account scan any other account's upload by counting.
      # The signature makes the id unguessable; the recorded uploader is
      # what actually enforces ownership.
      def self.resolve_attachments(ids, user)
        Array(ids).map(&:to_s).reject(&:blank?).filter_map do |id|
          blob = ActiveStorage::Blob.find_signed(id)
          blob if blob && blob.metadata["uploaded_by_user_id"].to_s == user.id.to_s
        end
      end
      private_class_method :resolve_attachments
    end
  end
end
