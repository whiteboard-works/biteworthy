require "rails_helper"
require "erb"
require "yaml"

# Guards the Cloudflare R2 fix: aws-sdk-core >= 3.201 adds a default CRC32
# request checksum, and R2 rejects any request with more than one checksum
# ("You can only specify one non-default checksum at a time"), 500-ing every
# blob upload (menu ingestion + dish photos). The r2 service must pin the
# checksum options to "when_required" so the SDK stops adding them.
RSpec.describe "R2 Active Storage config" do
  let(:config) do
    raw = ERB.new(File.read(Rails.root.join("config/storage.yml"))).result
    YAML.safe_load(raw, aliases: true)
  end

  it "disables the aws-sdk default request/response checksums (R2 rejects multi-checksum requests)" do
    expect(config.dig("r2", "request_checksum_calculation")).to eq("when_required")
    expect(config.dig("r2", "response_checksum_validation")).to eq("when_required")
  end
end
