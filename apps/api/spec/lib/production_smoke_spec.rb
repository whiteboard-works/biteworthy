require "rails_helper"
require "stringio"

# Phase 5.1 — guards the production smoke runner the rake task wraps.
RSpec.describe Biteworthy::ProductionSmoke do
  let(:logger) { StringIO.new }

  # Stub Net::HTTP-shaped responses so the spec doesn't hit a real
  # socket. Each `plan` entry maps a path to a Net::HTTPResponse.
  def fake_http(plan)
    Class.new do
      define_singleton_method(:new) do |_host, _port|
        instance = Object.new
        plan_ref = plan
        instance.define_singleton_method(:use_ssl=) { |_| nil }
        instance.define_singleton_method(:read_timeout=) { |_| nil }
        instance.define_singleton_method(:open_timeout=) { |_| nil }
        instance.define_singleton_method(:get) do |path, _headers = {}|
          plan_ref.fetch(path) do
            raise "no plan entry for #{path.inspect} (plans: #{plan_ref.keys.inspect})"
          end
        end
        instance
      end
    end
  end

  def ok_response(body = "{}")
    res = Net::HTTPOK.new("1.1", "200", "OK")
    res.instance_variable_set(:@read, true)
    res.instance_variable_set(:@body, body)
    res
  end

  def fail_response
    Net::HTTPInternalServerError.new("1.1", "500", "ISE")
  end

  describe "#run" do
    context "with no published restaurants in the DB" do
      it "passes /up + reports the items query as skipped" do
        http = fake_http("/up" => ok_response)
        runner = described_class.new(host: "https://api.example.com", logger: logger, http_client: http)

        ok = runner.run

        expect(ok).to be true
        expect(logger.string).to include("[OK ] GET /up")
        expect(logger.string).to include("status=skipped")
        expect(logger.string).to include("Phase 5.7's seed task will populate")
      end
    end

    context "with a published restaurant" do
      let!(:restaurant) { create(:restaurant, :published, slug: "ninis") }

      it "calls /up + the items query for that restaurant" do
        http = fake_http(
          "/up" => ok_response,
          "/api/v1/restaurants/ninis/items" => ok_response('{"items":[{"id":"a"},{"id":"b"}]}')
        )
        runner = described_class.new(host: "https://api.example.com", logger: logger, http_client: http)

        expect(runner.run).to be true
        expect(logger.string).to include("items=2")
        expect(logger.string).to include("→ all checks passed")
      end

      it "reports a non-2xx /up as failed without raising" do
        http = fake_http(
          "/up" => fail_response,
          "/api/v1/restaurants/ninis/items" => ok_response('{"items":[]}')
        )
        runner = described_class.new(host: "https://api.example.com", logger: logger, http_client: http)

        expect(runner.run).to be false
        expect(logger.string).to include("[FAIL] GET /up")
        expect(logger.string).to include("→ at least one check failed")
      end

      it "captures network errors as a single FAIL line" do
        boom_http = Class.new do
          def self.new(*)
            instance = Object.new
            instance.define_singleton_method(:use_ssl=) { |_| nil }
            instance.define_singleton_method(:read_timeout=) { |_| nil }
            instance.define_singleton_method(:open_timeout=) { |_| nil }
            instance.define_singleton_method(:get) { |*| raise Errno::ECONNREFUSED, "connection refused" }
            instance
          end
        end
        runner = described_class.new(host: "https://api.example.com", logger: logger, http_client: boom_http)

        expect(runner.run).to be false
        expect(logger.string).to include("status=error")
        expect(logger.string).to include("Errno::ECONNREFUSED")
      end
    end
  end
end
