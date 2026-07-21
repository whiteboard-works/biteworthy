module Api
  module V1
    # POST /api/v1/ingestion_runs
    #   { restaurant_id: <uuid>, inputs[]: <files> }
    # GET  /api/v1/ingestion_runs/:id
    #
    # Phase 2.6 — the mobile camera capture flow uploads here. The
    # endpoint creates the run, attaches the images, and kicks off the
    # ExtractMenuJob via the state machine.
    #
    # Phase 6.1 — open to any authenticated user (was admin-only).
    # Non-admins are bounded by a per-user rolling-24h run quota and a
    # global daily API-spend ceiling; admins bypass both. Community
    # trust handling (suggested-confidence promotion) is Phase 6.3.
    class IngestionRunsController < BaseController
      def create
        restaurant  = Restaurant.find(params.require(:restaurant_id))
        files       = Array(params[:inputs]).reject(&:blank?)
        source_url  = params[:source_url].to_s.presence
        source_text = params[:source_text].to_s.presence

        # Phase 6.2 ownership rule: non-admins may scan drafts they
        # created (the new-restaurant flow) or published restaurants
        # (re-scans). Another user's draft is off limits — drafts are
        # invisible work-in-progress until their creator publishes.
        unless can_target_restaurant?(restaurant)
          render json: { error: "forbidden_restaurant" }, status: :forbidden
          return
        end

        if files.empty? && source_url.nil? && source_text.nil?
          render json: { error: "no_inputs" }, status: :unprocessable_entity
          return
        end

        return unless validate_files!(files)
        return unless validate_source_text!(source_text)

        # Cheap unlocked pre-check so an over-quota caller can't make
        # us do an outbound URL fetch (codex P2 on #298). Advisory only
        # — the authoritative check re-runs under the lock below.
        return unless enforce_community_limits!

        # URL fetch happens BEFORE the per-user lock — an upstream
        # server's slowness must not extend how long we hold a DB
        # transaction + advisory lock.
        fetched = nil
        if source_url
          begin
            fetched = UrlFetcher.fetch(source_url)
          rescue UrlFetcher::FetchError => e
            render json: { error: "url_fetch_failed", reason: e.reason, status: e.status },
                   status: :unprocessable_entity
            return
          end
        end

        # The quota check and the INSERT must be atomic per user, or
        # parallel requests just under the quota all pass the read and
        # all insert (codex P2 on #297). pg_advisory_xact_lock keyed on
        # the user id serializes them; admins skip the lock entirely.
        with_per_user_serialization do
          next unless enforce_community_limits!

          if fetched
            create_from_fetched(restaurant, source_url, fetched)
          elsif source_text
            create_from_text(restaurant, source_text)
          else
            create_from_files(restaurant, files)
          end
        end
      end

      def show
        run = IngestionRun.find(params[:id])
        # Allow the run's owner OR an admin to read it. Anyone else 404s.
        if run.user_id != current_user.id && !current_user.is_admin?
          render json: { error: "not_found" }, status: :not_found
          return
        end
        render json: serialize_run(run)
      end

      private

      def create_from_files(restaurant, files)
        run = IngestionRun.create!(
          user:       current_user,
          restaurant: restaurant,
          input_kind: detect_input_kind(files.first)
        )
        run.inputs.attach(files)
        run.transition_to!(:extracting)

        render json: serialize_run(run), status: :created
      end

      def create_from_fetched(restaurant, source_url, result)
        run = IngestionRun.create!(
          user:       current_user,
          restaurant: restaurant,
          input_kind: result.content_type.include?("pdf") ? "pdf" : "url",
          source_url: source_url
        )
        run.inputs.attach(
          io:           result.io,
          filename:     result.filename,
          content_type: result.content_type
        )
        run.transition_to!(:extracting)

        render json: serialize_run(run), status: :created
      end

      # Copy/paste path — the user pastes raw menu text instead of a
      # file/URL. Stored as a text/plain input blob so it flows through
      # the same pipeline; ExtractMenuPrompt sends text blobs as a text
      # content block (not an image).
      def create_from_text(restaurant, text)
        run = IngestionRun.create!(
          user:       current_user,
          restaurant: restaurant,
          input_kind: "text"
        )
        run.inputs.attach(
          io:           StringIO.new(text),
          filename:     "pasted-menu.txt",
          content_type: "text/plain"
        )
        run.transition_to!(:extracting)

        render json: serialize_run(run), status: :created
      end

      PER_USER_DAILY_RUNS_DEFAULT      = 5
      DAILY_COST_CEILING_CENTS_DEFAULT = 2_000 # $20/day across all non-admin spend
      MAX_INPUT_FILES_DEFAULT          = 10
      MAX_INPUT_FILE_BYTES_DEFAULT     = 10 * 1024 * 1024 # match UrlFetcher's 10 MB cap
      MAX_SOURCE_TEXT_CHARS_DEFAULT    = 50_000           # a very long menu is well under this

      ALLOWED_INPUT_CONTENT_TYPES = %w[
        image/jpeg image/png image/heic image/heif image/webp application/pdf
      ].freeze

      # Direct multipart uploads need the same bounds the URL path has
      # had since Phase 2.8 (codex P2 on #297). Applies to admins too —
      # the extraction job base64-encodes every byte into the prompt,
      # so oversized inputs hurt regardless of who sent them.
      def validate_files!(files)
        return true if files.empty?

        if files.size > max_input_files
          render json: { error: "too_many_files", limit: max_input_files },
                 status: :unprocessable_entity
          return false
        end

        if files.any? { |f| f.size.to_i > max_input_file_bytes }
          render json: { error: "file_too_large", limit_bytes: max_input_file_bytes },
                 status: :unprocessable_entity
          return false
        end

        if files.any? { |f| ALLOWED_INPUT_CONTENT_TYPES.exclude?(f.content_type.to_s) }
          render json: { error: "unsupported_file_type", allowed: ALLOWED_INPUT_CONTENT_TYPES },
                 status: :unprocessable_entity
          return false
        end

        true
      end

      def can_target_restaurant?(restaurant)
        return true if current_user&.is_admin?
        return true if restaurant.status == "published"

        restaurant.status == "draft" && restaurant.created_by_user_id == current_user.id
      end

      def with_per_user_serialization(&block)
        return yield if current_user&.is_admin?

        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array(
              ["SELECT pg_advisory_xact_lock(hashtext(?))", current_user.id]
            )
          )
          block.call
        end
      end

      # Returns true when within limits; renders + returns false otherwise.
      def enforce_community_limits!
        return true if current_user&.is_admin?

        if runs_in_last_24h >= per_user_daily_limit
          render json: { error: "quota_exceeded", limit: per_user_daily_limit },
                 status: :too_many_requests
          return false
        end

        if todays_spend_cents >= daily_cost_ceiling_cents
          render json: { error: "cost_ceiling_reached" }, status: :service_unavailable
          return false
        end

        true
      end

      def runs_in_last_24h
        IngestionRun.where(user_id: current_user.id)
                    .where(created_at: 24.hours.ago..)
                    .count
      end

      def todays_spend_cents
        IngestionRun.where(created_at: Time.current.utc.beginning_of_day..)
                    .sum(:api_cost_cents)
      end

      def per_user_daily_limit
        Integer(ENV.fetch("INGESTION_RUNS_PER_USER_PER_DAY", PER_USER_DAILY_RUNS_DEFAULT))
      end

      def daily_cost_ceiling_cents
        Integer(ENV.fetch("INGESTION_DAILY_COST_CEILING_CENTS", DAILY_COST_CEILING_CENTS_DEFAULT))
      end

      def max_input_files
        Integer(ENV.fetch("INGESTION_MAX_INPUT_FILES", MAX_INPUT_FILES_DEFAULT))
      end

      def max_input_file_bytes
        Integer(ENV.fetch("INGESTION_MAX_INPUT_FILE_BYTES", MAX_INPUT_FILE_BYTES_DEFAULT))
      end

      def max_source_text_chars
        Integer(ENV.fetch("INGESTION_MAX_SOURCE_TEXT_CHARS", MAX_SOURCE_TEXT_CHARS_DEFAULT))
      end

      # Pasted-text bound — mirrors the multipart file caps (codex P2 on
      # #297): the extraction prompt puts the whole thing in the request,
      # so cap it regardless of who sent it.
      def validate_source_text!(text)
        return true if text.nil?

        if text.length > max_source_text_chars
          render json: { error: "text_too_large", limit_chars: max_source_text_chars },
                 status: :unprocessable_entity
          return false
        end

        true
      end

      def detect_input_kind(file)
        ct = file.respond_to?(:content_type) ? file.content_type.to_s : ""
        return "pdf" if ct.include?("pdf")
        "photo"
      end

      def serialize_run(run)
        {
          id:               run.id,
          status:           run.status,
          input_kind:       run.input_kind,
          restaurant_id:    run.restaurant_id,
          state_history:    run.state_history,
          failure_message:  run.failure_message,
          api_cost_cents:   run.api_cost_cents,
          latency_ms:       run.latency_ms,
          input_count:      run.inputs.attached? ? run.inputs.count : 0,
          ingestion_items_count: run.ingestion_items.count,
          created_at:       run.created_at,
          updated_at:       run.updated_at
        }
      end
    end
  end
end
