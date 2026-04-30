# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "benchmark"

# Phase 5.1 — production smoke runner.
#
# Hits the deployed API on three reads in sequence, prints a one-line
# summary per check, returns true iff every check passed. Wrapped by
# the `biteworthy:production:smoke` rake task with HOST + ENV defaults.
#
# The runner stays read-only on purpose — Phase 5.7's seed task is
# the right place to exercise IngestionRun creation against prod, so
# this can run from CI on every deploy without polluting the DB.
module Biteworthy
  class ProductionSmoke
    CheckResult = Struct.new(:name, :ok, :status, :elapsed_ms, :detail, keyword_init: true)

    def initialize(host:, logger:, http_client: Net::HTTP)
      @host        = host.chomp("/")
      @logger      = logger
      @http_client = http_client
    end

    def run
      results = []
      results << check_up
      results << check_items_query

      log_summary(results)
      results.all?(&:ok)
    end

    private

    def check_up
      timed("GET /up") do
        response = get("/up")
        ok       = response.is_a?(Net::HTTPSuccess)
        [ok, response.code, ok ? "alive" : "expected 2xx, got #{response.code}"]
      end
    end

    def check_items_query
      restaurant = Restaurant.published.order(:created_at).first

      return CheckResult.new(
        name:      "GET /api/v1/restaurants/:slug/items",
        ok:        true,
        status:    "skipped",
        elapsed_ms: 0,
        detail:    "no published restaurant in DB; Phase 5.7's seed task will populate"
      ) if restaurant.nil?

      timed("GET /api/v1/restaurants/#{restaurant.slug}/items") do
        response = get("/api/v1/restaurants/#{restaurant.slug}/items")
        ok       = response.is_a?(Net::HTTPSuccess)
        detail   = if ok
                     body = JSON.parse(response.body) rescue {}
                     "items=#{(body["items"] || []).size}"
                   else
                     "expected 2xx, got #{response.code}"
                   end
        [ok, response.code, detail]
      end
    end

    # Wrap a block that returns [ok, status, detail] in timing + struct
    # construction. Catches network errors so the task reports them
    # rather than crashing partway through.
    def timed(name)
      elapsed_ms = nil
      ok, status, detail = nil
      elapsed_ms = (Benchmark.realtime { ok, status, detail = yield } * 1000).round
      CheckResult.new(name: name, ok: ok, status: status, elapsed_ms: elapsed_ms, detail: detail)
    rescue StandardError => e
      CheckResult.new(
        name:       name,
        ok:         false,
        status:     "error",
        elapsed_ms: elapsed_ms || 0,
        detail:     "#{e.class}: #{e.message}"
      )
    end

    def get(path)
      uri = URI.join(@host + "/", path.delete_prefix("/"))
      http = @http_client.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 10
      http.open_timeout = 5
      http.get(uri.request_uri, "Accept" => "application/json")
    end

    def log_summary(results)
      @logger.puts "BiteWorthy production smoke @ #{@host}"
      results.each do |r|
        mark = r.ok ? "OK " : "FAIL"
        @logger.puts "  [#{mark}] #{r.name}  status=#{r.status}  #{r.elapsed_ms}ms  #{r.detail}"
      end
      @logger.puts(results.all?(&:ok) ? "  → all checks passed" : "  → at least one check failed")
    end
  end
end
