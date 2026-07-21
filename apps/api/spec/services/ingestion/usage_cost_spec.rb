require "rails_helper"

RSpec.describe Ingestion::UsageCost do
  describe ".cents" do
    it "prices a vision-extraction-shaped call (big uncached input)" do
      # 100k input tokens at $3/MTok = 30 cents; 2k output at $15/MTok = 3 cents
      usage = { "input_tokens" => 100_000, "output_tokens" => 2_000,
                "cache_read_input_tokens" => 0, "cache_creation_input_tokens" => 0 }

      expect(described_class.cents(usage, model: "claude-sonnet-4-6")).to eq(33)
    end

    it "prices cache reads at a tenth of input and cache writes at 1.25x" do
      # 1M cache-read = 30 cents; 1M cache-write = 375 cents
      usage = { "input_tokens" => 0, "output_tokens" => 0,
                "cache_read_input_tokens" => 1_000_000,
                "cache_creation_input_tokens" => 1_000_000 }

      expect(described_class.cents(usage, model: "claude-sonnet-4-6")).to eq(405)
    end

    it "rounds sub-cent calls UP so the daily ceiling can't leak via many cheap calls" do
      usage = { "input_tokens" => 100, "output_tokens" => 100 }

      expect(described_class.cents(usage, model: "claude-sonnet-4-6")).to eq(1)
    end

    it "returns 0 for nil/blank usage (stubbed-client specs, failed calls)" do
      expect(described_class.cents(nil)).to eq(0)
      expect(described_class.cents({})).to eq(0)
    end

    it "prices the faster resolve model (haiku) at its own lower rate" do
      # 1M input at $1/MTok = 100 cents; 1M output at $5/MTok = 500 cents
      usage = { "input_tokens" => 1_000_000, "output_tokens" => 1_000_000 }

      expect(described_class.cents(usage, model: "claude-haiku-4-5-20251001")).to eq(600)
    end

    it "falls back to default-model pricing for unknown models" do
      usage = { "input_tokens" => 1_000_000 }

      expect(described_class.cents(usage, model: "some-future-model")).to eq(300)
    end
  end
end
