require "rails_helper"
require "stringio"
require "tempfile"

# Phase 5.7 — guards the Durango batch ingest runner. We don't move
# real bytes (no Anthropic, no real HTTP) — the contract-level
# question is "does the runner correctly find/create rows + start
# IngestionRuns + isolate per-row failures?" and that's answered by
# stubbing UrlFetcher.
RSpec.describe Biteworthy::DurangoSeed do
  let(:logger) { StringIO.new }

  # Stand-in for UrlFetcher — call counts + per-URL plan so the spec
  # can simulate "URL X fetches OK, URL Y times out."
  class FakeFetcher
    Result = Struct.new(:io, :content_type, :filename, :byte_size, keyword_init: true)

    def initialize(plan)
      @plan = plan
    end

    def fetch(url)
      action = @plan.fetch(url) { raise "no plan for #{url}" }
      raise action if action.is_a?(StandardError)
      action
    end
  end

  def fake_blob_result(filename: "menu.html", content_type: "text/html")
    FakeFetcher::Result.new(
      io:           StringIO.new("<html>fake menu</html>"),
      content_type: content_type,
      filename:     filename,
      byte_size:    24
    )
  end

  def write_csv(rows)
    tempfile = Tempfile.new(["durango", ".csv"])
    tempfile.write("name,slug,address,phone,website,menu_source,neighborhood\n")
    tempfile.write("# Comments are allowed inline.\n")
    rows.each { |r| tempfile.write(r + "\n") }
    tempfile.close
    tempfile.path
  end

  describe "#run" do
    it "find-or-creates the city + restaurants and kicks off ingestion runs" do
      csv = write_csv([
        "Tacos,tacos,1 Main,(970) 555,https://tacos.example,https://tacos.example/menu,Downtown",
        "Cream,cream,2 Main,(970) 666,https://cream.example,https://cream.example/menu,Downtown"
      ])
      fetcher = FakeFetcher.new(
        "https://tacos.example/menu" => fake_blob_result,
        "https://cream.example/menu" => fake_blob_result
      )

      result = described_class.new(
        csv_path:     csv,
        wait_seconds: 0,
        url_fetcher:  fetcher,
        logger:       logger
      ).run

      expect(City.where(slug: "durango").count).to eq(1)
      expect(Restaurant.where(slug: %w[tacos cream]).count).to eq(2)
      expect(IngestionRun.count).to eq(2)
      expect(IngestionRun.pluck(:status).uniq).to eq(%w[extracting])
      expect(result.created).to eq(2)
      expect(result.failed).to eq(0)
      expect(logger.string).to include("[ok  ]")
    end

    it "is idempotent — re-running skips restaurants that already have a non-failed run" do
      csv = write_csv([
        "Tacos,tacos,1 Main,,,https://tacos.example/menu,Downtown"
      ])
      fetcher = FakeFetcher.new("https://tacos.example/menu" => fake_blob_result)

      first = described_class.new(csv_path: csv, wait_seconds: 0, url_fetcher: fetcher, logger: StringIO.new).run
      expect(first.created).to eq(1)

      # Mark the run as :staged so the idempotence guard kicks in.
      IngestionRun.first.update!(status: "staged")

      second = described_class.new(csv_path: csv, wait_seconds: 0, url_fetcher: fetcher, logger: logger).run
      expect(second.skipped).to eq(1)
      expect(second.created).to eq(0)
      expect(logger.string).to include("[skip]")
      expect(IngestionRun.count).to eq(1) # no new run
    end

    it "isolates per-row failures so one bad URL doesn't kill the rest" do
      csv = write_csv([
        "Good,good,1 Main,,,https://good.example/menu,Downtown",
        "Bad,bad,2 Main,,,https://broken.example/menu,Downtown",
        "Also Good,also-good,3 Main,,,https://also.example/menu,Downtown"
      ])
      fetcher = FakeFetcher.new(
        "https://good.example/menu"   => fake_blob_result,
        "https://broken.example/menu" => UrlFetcher::FetchError.new("dns_failed", status: 0),
        "https://also.example/menu"   => fake_blob_result
      )

      result = described_class.new(
        csv_path:     csv,
        wait_seconds: 0,
        url_fetcher:  fetcher,
        logger:       logger
      ).run

      expect(result.created).to eq(2)
      expect(result.failed).to eq(1)
      bad_row = result.rows.find { |r| r.outcome == :failed }
      expect(bad_row.restaurant_slug).to eq("bad")
      expect(bad_row.detail).to include("dns_failed")
      expect(logger.string).to include("[FAIL]")
    end

    it "tallies created / skipped / failed in the summary line" do
      csv = write_csv([
        "Tacos,tacos,1 Main,,,https://tacos.example/menu,Downtown"
      ])
      fetcher = FakeFetcher.new("https://tacos.example/menu" => fake_blob_result)

      described_class.new(csv_path: csv, wait_seconds: 0, url_fetcher: fetcher, logger: logger).run

      expect(logger.string).to match(/created=1\s+skipped=0\s+failed=0/)
    end

    it "writes restaurants as :draft so the Phase 2.5 swipe-verify queue still gates publication" do
      csv = write_csv([
        "Tacos,tacos,1 Main,,,https://tacos.example/menu,Downtown"
      ])
      fetcher = FakeFetcher.new("https://tacos.example/menu" => fake_blob_result)

      described_class.new(csv_path: csv, wait_seconds: 0, url_fetcher: fetcher, logger: StringIO.new).run

      expect(Restaurant.find_by(slug: "tacos").status).to eq("draft")
    end

    it "skips comment lines (starting with #) + blank lines in the CSV" do
      csv_path = Tempfile.new(["durango", ".csv"]).tap do |f|
        f.write("name,slug,address,phone,website,menu_source,neighborhood\n")
        f.write("# Comment line, ignored\n")
        f.write("\n") # blank line, ignored
        f.write("Tacos,tacos,1 Main,,,https://tacos.example/menu,Downtown\n")
        f.close
      end.path
      fetcher = FakeFetcher.new("https://tacos.example/menu" => fake_blob_result)

      result = described_class.new(csv_path: csv_path, wait_seconds: 0, url_fetcher: fetcher, logger: StringIO.new).run

      expect(result.total).to eq(1)
      expect(result.created).to eq(1)
    end
  end
end
