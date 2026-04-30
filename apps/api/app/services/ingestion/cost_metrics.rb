# frozen_string_literal: true

# Phase 2.9 — aggregations behind the /admin/dashboard cost view.
#
# All numbers come straight from the IngestionRun columns Phase 2.3
# added (api_cost_cents / latency_ms / cached_input_tokens /
# uncached_input_tokens). Kept as a separate service so the spec
# can test the math without rendering HTML.
#
# Target line: $0.25 per 50-item menu = 0.5¢ per item. Anything
# above this in the dashboard's per-item-cost row should raise an
# eyebrow.
module Ingestion
  class CostMetrics
    TARGET_CENTS_PER_ITEM = 0.5  # $0.25 / 50 items

    PERIODS = {
      today:        { label: "Today",        range: -> { Time.current.beginning_of_day..Time.current.end_of_day } },
      last_7_days:  { label: "Last 7 days",  range: -> { 7.days.ago.beginning_of_day..Time.current.end_of_day } },
      last_30_days: { label: "Last 30 days", range: -> { 30.days.ago.beginning_of_day..Time.current.end_of_day } }
    }.freeze

    Bucket = Struct.new(
      :label, :run_count, :item_count, :total_cost_cents,
      :cost_per_item_cents, :avg_latency_ms, :p95_latency_ms,
      :cache_hit_rate, keyword_init: true
    )

    # Returns a hash keyed by period name → Bucket.
    def self.by_period
      PERIODS.each_with_object({}) do |(key, defn), out|
        out[key] = bucket_for(defn[:range].call, label: defn[:label])
      end
    end

    def self.bucket_for(range, label:)
      runs = IngestionRun.where(created_at: range)
      run_count   = runs.count
      total_cents = runs.sum(:api_cost_cents)
      cached      = runs.sum(:cached_input_tokens)
      uncached    = runs.sum(:uncached_input_tokens)
      total_in    = cached + uncached
      latencies   = runs.where.not(latency_ms: nil).pluck(:latency_ms)

      # Item count is denormalized from the run's IngestionItems —
      # `IngestionRun.has_many :ingestion_items`. Single COUNT join.
      item_count =
        if runs.exists?
          IngestionItem.where(ingestion_run_id: runs.select(:id)).count
        else
          0
        end

      Bucket.new(
        label:               label,
        run_count:           run_count,
        item_count:          item_count,
        total_cost_cents:    total_cents,
        cost_per_item_cents: item_count.zero? ? 0.0 : total_cents.to_f / item_count,
        avg_latency_ms:      latencies.empty? ? nil : (latencies.sum.to_f / latencies.size).round,
        p95_latency_ms:      percentile(latencies, 0.95),
        cache_hit_rate:      total_in.zero? ? 0.0 : cached.to_f / total_in
      )
    end

    # Nearest-rank percentile, returns nil for empty arrays.
    # k = 0.95 → 95th percentile.
    def self.percentile(values, k)
      return nil if values.empty?

      sorted = values.sort
      idx = ((sorted.size * k).ceil - 1).clamp(0, sorted.size - 1)
      sorted[idx]
    end
  end
end
