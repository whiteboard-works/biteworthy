# frozen_string_literal: true

module Ingestion
  # Creates an IngestionRun and kicks off extraction.
  #
  # This is where the community-scanning policy lives: who may scan what,
  # the per-user rolling-24h run quota, the global daily spend ceiling, and
  # the input size caps. It moved out of Api::V1::IngestionRunsController
  # when the chat replaced the upload form — the policy is the valuable
  # part and it must not evaporate with the controller.
  #
  # Returns a Result. Callers translate `error` into their own vocabulary
  # (an HTTP status, or an MCP tool error the model can act on).
  class StartRun
    Result = Struct.new(:run, :error, :detail, keyword_init: true) do
      def ok? = error.nil?
    end

    PER_USER_DAILY_RUNS_DEFAULT      = 5
    DAILY_COST_CEILING_CENTS_DEFAULT = 2_000 # $20/day across all non-admin spend
    MAX_INPUT_FILES_DEFAULT          = 10
    MAX_INPUT_FILE_BYTES_DEFAULT     = 10 * 1024 * 1024 # match UrlFetcher's 10 MB cap
    MAX_SOURCE_TEXT_CHARS_DEFAULT    = 50_000           # a very long menu is well under this
    # Headroom for the super tier — see `validate_files` for why these are
    # multiplied rather than dropped. 5× is well past any real menu and
    # still short of the request size that breaks the extraction call.
    SUPER_ADMIN_INPUT_MULTIPLIER     = 5

    ALLOWED_INPUT_CONTENT_TYPES = %w[
      image/jpeg image/png image/heic image/heif image/webp application/pdf
    ].freeze

    def self.call(...) = new(...).call

    # Exactly one input source is used, in this precedence: files, then
    # source_url, then source_text.
    def initialize(user:, restaurant:, files: [], source_url: nil, source_text: nil)
      @user        = user
      @restaurant  = restaurant
      @files       = Array(files).reject(&:blank?)
      @source_url  = source_url.to_s.presence
      @source_text = source_text.to_s.presence
    end

    def call
      guard = check_preconditions
      return guard if guard

      # The URL fetch happens BEFORE the per-user lock — an upstream
      # server's slowness must not extend how long we hold a DB
      # transaction and advisory lock.
      fetched = nil
      if @source_url
        begin
          fetched = UrlFetcher.fetch(@source_url)
        rescue UrlFetcher::FetchError => e
          return failure(:url_fetch_failed, reason: e.reason, status: e.status)
        end
      end

      result = nil
      with_per_user_serialization do
        # Re-checked under the lock: the pre-check above is advisory, and
        # parallel requests just under the quota would otherwise all pass
        # the read and all insert.
        result = enforce_limits || create_run(fetched)
      end
      result
    end

    private

    def check_preconditions
      return failure(:forbidden_restaurant) unless can_target_restaurant?
      return failure(:no_inputs) if @files.empty? && @source_url.nil? && @source_text.nil?

      validate_files || validate_source_text ||
        # Cheap unlocked pre-check so an over-quota caller can't make us do
        # an outbound URL fetch before being turned away.
        enforce_limits
    end

    # Non-admins may scan drafts they created (the new-restaurant flow) or
    # published restaurants (re-scans). Another user's draft is off limits —
    # drafts are invisible work-in-progress until their creator publishes.
    def can_target_restaurant?
      return true if @user&.is_admin?
      return true if @restaurant.status == "published"

      @restaurant.status == "draft" && @restaurant.created_by_user_id == @user&.id
    end

    # Applies to admins too — extraction base64-encodes every byte into the
    # prompt, so oversized inputs cost real money regardless of who sent them.
    # A super admin is the person whose money that is, so the tier above
    # admin gets `SUPER_ADMIN_INPUT_MULTIPLIER`× the headroom.
    #
    # **Raised, not removed**, and the reason is the same one the
    # content-type check gives below: these caps bound what
    # `ExtractMenuJob` base64-encodes into a single request, not just what
    # it costs. Dropping them entirely would let 40 × 30 MB of photos be
    # accepted, uploaded, and then die on an Anthropic request-size 400
    # (or take the box's memory with it) — a failure discovered after the
    # upload rather than at the door, which is exactly what the caps
    # exist to prevent.
    #
    # The content-type check is not a limit and is never skipped: a file
    # the extractor cannot read fails inside the vision call, after it has
    # been paid for, with an error about the model rather than the file.
    def validate_files
      return nil if @files.empty?

      return failure(:too_many_files, limit: file_count_limit) if @files.size > file_count_limit

      if @files.any? { |f| byte_size_of(f) > file_bytes_limit }
        return failure(:file_too_large, limit_bytes: file_bytes_limit)
      end

      if @files.any? { |f| ALLOWED_INPUT_CONTENT_TYPES.exclude?(f.content_type.to_s) }
        return failure(:unsupported_file_type, allowed: ALLOWED_INPUT_CONTENT_TYPES)
      end

      nil
    end

    def file_count_limit = max_input_files * input_multiplier
    def file_bytes_limit = max_input_file_bytes * input_multiplier
    def text_chars_limit = max_source_text_chars * input_multiplier

    def input_multiplier = super_admin? ? SUPER_ADMIN_INPUT_MULTIPLIER : 1

    # Two shapes arrive here: an uploaded file (`size`) from a multipart
    # request, and an ActiveStorage::Blob (`byte_size`) when the caller
    # uploaded first and referred to it by id, which is how the chat and
    # every MCP client do it.
    def byte_size_of(file)
      (file.respond_to?(:byte_size) ? file.byte_size : file.size).to_i
    end

    def validate_source_text
      return nil if @source_text.nil?
      return nil if @source_text.length <= text_chars_limit

      failure(:text_too_large, limit_chars: text_chars_limit)
    end

    def super_admin? = !!@user&.is_super_admin?

    def enforce_limits
      return nil if @user&.is_admin?

      return failure(:quota_exceeded, limit: per_user_daily_limit) if runs_in_last_24h >= per_user_daily_limit
      return failure(:cost_ceiling_reached) if todays_spend_cents >= daily_cost_ceiling_cents

      nil
    end

    def with_per_user_serialization(&block)
      return yield if @user&.is_admin?

      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(
            ["SELECT pg_advisory_xact_lock(hashtext(?))", @user.id]
          )
        )
        block.call
      end
    end

    def create_run(fetched)
      run = if fetched
              build_from_fetched(fetched)
            elsif @source_text
              build_from_text
            else
              build_from_files
            end

      run.transition_to!(:extracting)
      ExtractMenuJob.perform_later(run.id)

      Result.new(run: run)
    end

    def build_from_files
      run = IngestionRun.create!(user: @user, restaurant: @restaurant,
                                 input_kind: detect_input_kind(@files.first))
      run.inputs.attach(@files)
      run
    end

    def build_from_fetched(fetched)
      run = IngestionRun.create!(
        user:       @user,
        restaurant: @restaurant,
        input_kind: fetched.content_type.include?("pdf") ? "pdf" : "url",
        source_url: @source_url
      )
      run.inputs.attach(io: fetched.io, filename: fetched.filename, content_type: fetched.content_type)
      run
    end

    # Pasted text is stored as a text/plain blob so it flows through the
    # same pipeline; ExtractMenuPrompt sends text blobs as a text content
    # block rather than an image.
    def build_from_text
      run = IngestionRun.create!(user: @user, restaurant: @restaurant, input_kind: "text")
      run.inputs.attach(io: StringIO.new(@source_text), filename: "pasted-menu.txt",
                        content_type: "text/plain")
      run
    end

    def detect_input_kind(file)
      ct = file.respond_to?(:content_type) ? file.content_type.to_s : ""
      ct.include?("pdf") ? "pdf" : "photo"
    end

    # Failed runs don't count against the per-user quota — a scan that
    # errored produced no value and the user must be able to retry. Spend is
    # still guarded separately by the ceiling, which sums EVERY run's billed
    # cost including failures, so a burst of failing calls can't leak past
    # the budget.
    def runs_in_last_24h
      IngestionRun.where(user_id: @user.id)
                  .where(created_at: 24.hours.ago..)
                  .where.not(status: "failed")
                  .count
    end

    def todays_spend_cents
      IngestionRun.where(created_at: Time.current.utc.beginning_of_day..).sum(:api_cost_cents)
    end

    def failure(error, **detail)
      Result.new(error: error, detail: detail)
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
  end
end
