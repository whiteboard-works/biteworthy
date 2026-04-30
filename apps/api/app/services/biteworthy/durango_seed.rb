# frozen_string_literal: true

require "csv"

# Phase 5.7 — operator-driven batch ingest of Durango restaurants.
#
# Reads a CSV (template at `docs/seeds/durango.csv.example`),
# find-or-creates each Restaurant in the durango City, kicks off
# an IngestionRun via the Phase 2.8 URL/PDF entrypoint, polls until
# the run hits `:staged` or `:failed` (or the per-run timeout
# elapses), prints one status line per row, returns a tally.
#
# Idempotent: a row whose Restaurant already has a non-failed
# IngestionRun in `:staged` or `:published` is skipped (the runner
# logs `[skip]`). To re-run a failed restaurant, mark its old runs
# as `:failed` (Avo can do this) or delete them — the next seed
# call will pick the row up.
#
# Doesn't auto-publish the run. The Phase 2.5 swipe-verify queue
# still gates publication via the 80%-accepted threshold; the seed
# task's job is to land 30 staged runs, not to bypass human review.
module Biteworthy
  class DurangoSeed
    DEFAULT_WAIT_SECONDS = 600 # 10 minutes per run, conservative
    POLL_INTERVAL_SEC    = 5

    Result = Struct.new(:created, :skipped, :failed, :rows, keyword_init: true) do
      def total
        created + skipped + failed
      end
    end

    Row = Struct.new(:restaurant_slug, :outcome, :detail, keyword_init: true)

    def initialize(
      csv_path:,
      city_slug: "durango",
      city_name: "Durango",
      city_region: "CO",
      logger: $stdout,
      wait_seconds: DEFAULT_WAIT_SECONDS,
      url_fetcher: UrlFetcher,
      operator_user: nil
    )
      @csv_path        = csv_path
      @city_slug       = city_slug
      @city_name       = city_name
      @city_region     = city_region
      @logger          = logger
      @wait_seconds    = wait_seconds
      @url_fetcher     = url_fetcher
      @operator_user   = operator_user
    end

    def run
      city = find_or_create_city!
      result = Result.new(created: 0, skipped: 0, failed: 0, rows: [])

      @logger.puts "BiteWorthy seed → city=#{city.slug}  csv=#{@csv_path}"

      parse_rows.each do |row|
        slug = row.fetch(:slug).presence || row.fetch(:name).parameterize
        outcome = process(row.merge(slug: slug), city)
        result.rows << outcome

        case outcome.outcome
        when :created  then result.created += 1
        when :skipped  then result.skipped += 1
        when :failed   then result.failed  += 1
        end

        @logger.puts "  [#{label(outcome.outcome)}] #{outcome.restaurant_slug.ljust(30)} #{outcome.detail}"
      end

      @logger.puts "  → created=#{result.created}  skipped=#{result.skipped}  failed=#{result.failed}"
      result
    end

    private

    def label(outcome)
      case outcome
      when :created then "ok  "
      when :skipped then "skip"
      when :failed  then "FAIL"
      else outcome.to_s.upcase
      end
    end

    def find_or_create_city!
      City.find_or_create_by!(slug: @city_slug) do |c|
        c.name   = @city_name
        c.region = @city_region
      end
    end

    # Skip comment lines + blank lines. Tolerate trailing whitespace.
    def parse_rows
      lines = File.readlines(@csv_path).reject { |l| l.strip.empty? || l.start_with?("#") }
      CSV.parse(lines.join, headers: true).map do |csv_row|
        csv_row.to_h.transform_keys(&:to_sym).transform_values { |v| v.to_s.strip }
      end
    end

    def process(row, city)
      restaurant = find_or_create_restaurant!(row, city)

      if previously_seeded?(restaurant)
        return Row.new(
          restaurant_slug: restaurant.slug,
          outcome:         :skipped,
          detail:          "already has a non-failed run"
        )
      end

      run = create_ingestion_run(restaurant, row.fetch(:menu_source))
      poll_until_complete(run)

      Row.new(
        restaurant_slug: restaurant.slug,
        outcome:         run.failed? ? :failed : :created,
        detail:          run.failed? ? (run.failure_message.to_s.truncate(120)) : "run=#{run.id} status=#{run.status}"
      )
    rescue StandardError => e
      Row.new(
        restaurant_slug: row[:slug] || row[:name],
        outcome:         :failed,
        detail:          "#{e.class}: #{e.message.to_s.truncate(120)}"
      )
    end

    def find_or_create_restaurant!(row, city)
      Restaurant.find_or_create_by!(city: city, slug: row.fetch(:slug)) do |r|
        r.name    = row.fetch(:name)
        r.phone   = row[:phone].presence
        r.website = row[:website].presence
        r.about   = row[:neighborhood].presence ? "Neighborhood: #{row[:neighborhood]}" : nil
        # Restaurants stay :draft until the swipe-verify threshold flips
        # them. The Phase 2.5 publish path takes over from there.
        r.status = "draft"
      end
    end

    def previously_seeded?(restaurant)
      # Restaurant has no has_many :ingestion_runs association; query
      # directly so we don't add one for this single check.
      IngestionRun.where(restaurant_id: restaurant.id, status: %w[staged published]).exists?
    end

    def create_ingestion_run(restaurant, menu_source)
      run = IngestionRun.create!(
        user:       @operator_user,
        restaurant: restaurant,
        input_kind: input_kind_for(menu_source),
        source_url: menu_source.start_with?("http") ? menu_source : nil
      )
      attach_input!(run, menu_source)
      run.transition_to!(:extracting)
      run
    end

    def input_kind_for(menu_source)
      return "pdf" if menu_source.downcase.end_with?(".pdf")
      return "url" if menu_source.start_with?("http")
      "photo"
    end

    # URL → fetch via UrlFetcher (handles redirects + 10MB cap).
    # Local path → open the file directly. Anything else → raise.
    def attach_input!(run, menu_source)
      if menu_source.start_with?("http")
        result = @url_fetcher.fetch(menu_source)
        run.inputs.attach(io: result.io, filename: result.filename, content_type: result.content_type)
      elsif File.exist?(menu_source)
        run.inputs.attach(
          io:           File.open(menu_source, "rb"),
          filename:     File.basename(menu_source),
          content_type: content_type_for(menu_source)
        )
      else
        raise UrlFetcher::FetchError.new("invalid_menu_source: #{menu_source}")
      end
    end

    def content_type_for(path)
      case File.extname(path).downcase
      when ".pdf"  then "application/pdf"
      when ".png"  then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".webp" then "image/webp"
      else "application/octet-stream"
      end
    end

    def poll_until_complete(run)
      return run if @wait_seconds <= 0
      deadline = Time.current + @wait_seconds
      loop do
        run.reload
        return run if run.staged? || run.published? || run.failed?
        break if Time.current >= deadline
        sleep(POLL_INTERVAL_SEC)
      end
      run
    end
  end
end
