require "rails_helper"
require "stringio"

# Phase 5.3 — guards the ActiveStorage migration runner the rake
# task wraps. We don't actually move bytes — the test env only
# configures the `:test` service, and the contract-level question
# (does the runner correctly route by `service_name`?) is answered
# by stubbing the services hash.
RSpec.describe Biteworthy::StorageBackfill do
  let(:logger) { StringIO.new }

  # Tiny stand-in for an ActiveStorage::Service. open() yields a
  # buffer; upload() records the keys it received so the spec can
  # assert "we attempted to write to the right service."
  class FakeService
    attr_reader :uploaded_keys

    def initialize(name, raise_on: nil)
      @name = name
      @uploaded_keys = []
      @raise_on = raise_on
    end

    def open(_key, **_)
      raise @raise_on, "boom from #{@name}" if @raise_on
      yield StringIO.new("payload from #{@name}")
    end

    def upload(key, _io, **_)
      @uploaded_keys << key
    end
  end

  def stub_services!(services)
    allow(ActiveStorage::Blob).to receive(:services).and_return(services)
  end

  def make_blob(service_name:, key: SecureRandom.uuid)
    # Blobs are normally created via attachments; building one
    # directly with a chosen service_name lets us cover the
    # migration branch without uploading actual bytes.
    ActiveStorage::Blob.create!(
      key:           key,
      filename:      "fixture.bin",
      service_name:  service_name,
      byte_size:     0,
      checksum:      "00000000000000000000000000",
      content_type:  "application/octet-stream"
    )
  end

  describe "#run" do
    it "skips blobs already on the target service (idempotent re-run)" do
      stub_services!("test" => FakeService.new("test"))
      make_blob(service_name: "test")

      result = described_class.new(target_service: "test", logger: logger).run

      expect(result.skipped).to eq(1)
      expect(result.migrated).to eq(0)
      expect(result.failed).to eq(0)
      expect(logger.string).to include("[skip]")
      expect(logger.string).to include("already on test")
    end

    it "migrates blobs whose service_name differs from the target" do
      target_service = FakeService.new("r2")
      stub_services!("test" => FakeService.new("test"), "r2" => target_service)
      blob = make_blob(service_name: "test")

      result = described_class.new(target_service: "r2", logger: logger).run

      expect(result.migrated).to eq(1)
      expect(target_service.uploaded_keys).to eq([blob.key])
      expect(blob.reload.service_name).to eq("r2")
      expect(logger.string).to include("[ok]")
      expect(logger.string).to include("test → r2")
    end

    it "captures per-blob failures without aborting the run" do
      flaky_source = FakeService.new("test", raise_on: Errno::ECONNRESET)
      target       = FakeService.new("r2")
      stub_services!("test" => flaky_source, "r2" => target)

      make_blob(service_name: "test", key: "blob-a")  # will fail on download
      make_blob(service_name: "r2")                   # already on target

      result = described_class.new(target_service: "r2", logger: logger).run

      expect(result.failed).to eq(1)
      expect(result.skipped).to eq(1)
      expect(result.migrated).to eq(0)
      expect(logger.string).to include("[FAIL]")
      expect(logger.string).to include("Errno::ECONNRESET")
    end

    it "summarizes the run with migrated / skipped / failed counts" do
      target = FakeService.new("r2")
      stub_services!("test" => FakeService.new("test"), "r2" => target)
      make_blob(service_name: "test")
      make_blob(service_name: "r2")
      make_blob(service_name: "r2")

      described_class.new(target_service: "r2", logger: logger).run

      expect(logger.string).to match(/migrated=1\s+skipped=2\s+failed=0/)
    end
  end
end
