# frozen_string_literal: true

module Ingestion
  # Jev health for /admin/dashboard and the scan queue, read off
  # `jev_observations` the way CostMetrics reads IngestionRun. Same three
  # period windows, so the two sets of tiles answer the same question for
  # the same days.
  #
  # Cost is derived, not stored: TypeSafe bills input tokens only, at
  # $0.042 per million (docs.typesafe.ai/models), so the ledger keeps
  # tokens and this applies the rate. A rate change is one constant.
  class JevMetrics
    CENTS_PER_MTOK = 4.2

    Bucket = Struct.new(:label, :calls, :answered, :partial, :failed, :input_tokens, :cost_cents,
                        :cuisine, :wheat, keyword_init: true)

    # jsonb sums for the counters each kind writes into `details`. Named
    # here rather than interpolated so no caller can reach the SQL.
    DETAIL_SUMS = {
      tagged:     Arel.sql("COALESCE(SUM((details->>'tagged')::integer), 0)"),
      no_cuisine: Arel.sql("COALESCE(SUM((details->>'no_cuisine')::integer), 0)"),
      jev_only:   Arel.sql("COALESCE(SUM((details->>'jev_only')::integer), 0)"),
      data_only:  Arel.sql("COALESCE(SUM((details->>'data_only')::integer), 0)")
    }.freeze

    def self.by_period
      CostMetrics::PERIODS.each_with_object({}) do |(key, defn), out|
        out[key] = bucket_for(defn[:range].call, label: defn[:label])
      end
    end

    def self.bucket_for(range, label:)
      rows     = JevObservation.where(created_at: range)
      outcomes = rows.group(:outcome).count
      tokens   = rows.sum(:input_tokens)
      cuisine  = rows.where(kind: "cuisine")
      wheat    = rows.where(kind: "hidden_wheat_shadow")

      Bucket.new(
        label:        label,
        calls:        rows.count,
        answered:     outcomes["answered"] || 0,
        partial:      outcomes["partial"] || 0,
        failed:       outcomes["failed"] || 0,
        input_tokens: tokens,
        cost_cents:   (tokens * CENTS_PER_MTOK / 1_000_000.0).round(3),
        cuisine: {
          calls:      cuisine.count,
          failed:     cuisine.where(outcome: "failed").count,
          tagged:     cuisine.pick(DETAIL_SUMS[:tagged]).to_i,
          no_cuisine: cuisine.pick(DETAIL_SUMS[:no_cuisine]).to_i
        },
        wheat: {
          calls:     wheat.count,
          agree:     wheat.where(agree: true).count,
          disagree:  wheat.where(agree: false).count,
          jev_only:  wheat.pick(DETAIL_SUMS[:jev_only]).to_i,
          data_only: wheat.pick(DETAIL_SUMS[:data_only]).to_i
        }
      )
    end

    # The queue's per-run rollup, one query for a page of runs:
    # { run_id => { calls:, failed:, input_tokens:, wheat_jev_only: } }.
    # `wheat_jev_only` is the number this exists to surface: dishes where
    # Jev said wheat and the data said none.
    def self.for_runs(run_ids)
      return {} if run_ids.empty?

      JevObservation.where(subject_type: "IngestionRun", subject_id: run_ids)
                    .group(:subject_id)
                    .pluck(
                      :subject_id,
                      Arel.sql("COUNT(*)"),
                      Arel.sql("COUNT(*) FILTER (WHERE outcome = 'failed')"),
                      Arel.sql("COALESCE(SUM(input_tokens), 0)"),
                      Arel.sql("COALESCE(SUM(CASE WHEN kind = 'hidden_wheat_shadow' " \
                               "THEN (details->>'jev_only')::integer END), 0)")
                    )
                    .to_h do |id, calls, failed, tokens, jev_only|
                      [ id, { calls: calls, failed: failed, input_tokens: tokens, wheat_jev_only: jev_only } ]
                    end
    end

    EMPTY_RUN = { calls: 0, failed: 0, input_tokens: 0, wheat_jev_only: 0 }.freeze
  end
end
