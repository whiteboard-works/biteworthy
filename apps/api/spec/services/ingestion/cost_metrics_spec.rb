require "rails_helper"

RSpec.describe Ingestion::CostMetrics do
  let(:restaurant) { create(:restaurant, :published) }

  describe ".by_period" do
    it "returns a Bucket per defined period (today / 7d / 30d)" do
      result = described_class.by_period

      expect(result.keys).to eq(%i[today last_7_days last_30_days])
      expect(result.values).to all(be_a(Ingestion::CostMetrics::Bucket))
    end

    it "computes totals across runs in the period" do
      run_today = create(:ingestion_run, restaurant: restaurant,
                         api_cost_cents: 12, latency_ms: 4_000,
                         cached_input_tokens: 8_000, uncached_input_tokens: 2_000)
      create(:ingestion_item, ingestion_run: run_today)
      create(:ingestion_item, ingestion_run: run_today)

      old_run = create(:ingestion_run, restaurant: restaurant,
                       api_cost_cents: 99, latency_ms: 9_999,
                       cached_input_tokens: 0, uncached_input_tokens: 50_000)
      old_run.update_column(:created_at, 60.days.ago)
      create(:ingestion_item, ingestion_run: old_run)

      bucket = described_class.by_period[:today]

      expect(bucket.run_count).to        eq(1)
      expect(bucket.item_count).to       eq(2)
      expect(bucket.total_cost_cents).to eq(12)
      expect(bucket.cost_per_item_cents).to eq(6.0)
      expect(bucket.avg_latency_ms).to   eq(4_000)
      expect(bucket.p95_latency_ms).to   eq(4_000)
      expect(bucket.cache_hit_rate).to   be_within(0.001).of(0.8) # 8000 / 10000
    end

    it "returns zero/nil safely when there are no runs in a period" do
      bucket = described_class.by_period[:today]

      expect(bucket.run_count).to        eq(0)
      expect(bucket.item_count).to       eq(0)
      expect(bucket.total_cost_cents).to eq(0)
      expect(bucket.cost_per_item_cents).to eq(0.0)
      expect(bucket.avg_latency_ms).to   be_nil
      expect(bucket.p95_latency_ms).to   be_nil
      expect(bucket.cache_hit_rate).to   eq(0.0)
    end

    it "handles a run with zero items (cost-per-item stays at 0, no division)" do
      create(:ingestion_run, restaurant: restaurant,
             api_cost_cents: 8, latency_ms: 1_500,
             cached_input_tokens: 1_000, uncached_input_tokens: 500)

      bucket = described_class.by_period[:today]

      expect(bucket.cost_per_item_cents).to eq(0.0)
    end
  end

  describe ".percentile" do
    it "returns nil for empty input" do
      expect(described_class.percentile([], 0.95)).to be_nil
    end

    it "returns the nearest-rank p95 for a 10-value sample" do
      values = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1_000]
      expect(described_class.percentile(values, 0.95)).to eq(1_000)
    end

    it "returns the nearest-rank p50 for a 10-value sample" do
      values = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1_000]
      expect(described_class.percentile(values, 0.5)).to eq(500)
    end

    it "returns the only value when the sample size is 1" do
      expect(described_class.percentile([42], 0.95)).to eq(42)
    end
  end
end
