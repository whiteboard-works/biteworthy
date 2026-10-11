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

    EMPTY_RUN = { calls: 0, failed: 0, input_tokens: 0, wheat_jev_only: 0 }.freeze

    Bucket = Struct.new(:label, :calls, :answered, :partial, :failed, :input_tokens, :cost_cents,
                        :cuisine, :wheat, keyword_init: true)

    # The counters each kind writes into `details`, summed only where the
    # value is a JSON number: a stray string in one row must not turn the
    # whole dashboard into a 500. Four literals rather than a builder, so
    # there is no string ever assembled into SQL.
    DETAIL_SUMS = {
      tagged:     Arel.sql("COALESCE(SUM(CASE WHEN jsonb_typeof(details->'tagged') = 'number' " \
                           "THEN (details->>'tagged')::integer END), 0)"),
      no_cuisine: Arel.sql("COALESCE(SUM(CASE WHEN jsonb_typeof(details->'no_cuisine') = 'number' " \
                           "THEN (details->>'no_cuisine')::integer END), 0)"),
      jev_only:   Arel.sql("COALESCE(SUM(CASE WHEN jsonb_typeof(details->'jev_only') = 'number' " \
                           "THEN (details->>'jev_only')::integer END), 0)"),
      data_only:  Arel.sql("COALESCE(SUM(CASE WHEN jsonb_typeof(details->'data_only') = 'number' " \
                           "THEN (details->>'data_only')::integer END), 0)")
    }.freeze
    DETAIL_KEYS = DETAIL_SUMS.keys.freeze

    def self.by_period
      CostMetrics::PERIODS.each_with_object({}) do |(key, defn), out|
        out[key] = bucket_for(defn[:range].call, label: defn[:label])
      end
    end

    # One grouped query per period: every (kind, outcome, agree) cell with
    # its count, tokens and summed counters, folded in Ruby.
    def self.bucket_for(range, label:)
      cells = JevObservation.where(created_at: range)
                            .group(:kind, :outcome, :agree)
                            .pluck(:kind, :outcome, :agree,
                                   Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(input_tokens), 0)"),
                                   *DETAIL_SUMS.values)
                            .map { |kind, outcome, agree, count, tokens, *sums|
                              { kind: kind, outcome: outcome, agree: agree, count: count, tokens: tokens,
                                **DETAIL_KEYS.zip(sums).to_h }
                            }
      cuisine = cells.select { |c| c[:kind] == "cuisine" }
      wheat   = cells.select { |c| c[:kind] == "hidden_wheat_shadow" }
      tokens  = cells.sum { |c| c[:tokens] }

      Bucket.new(
        label:        label,
        calls:        cells.sum { |c| c[:count] },
        answered:     cells.select { |c| c[:outcome] == "answered" }.sum { |c| c[:count] },
        partial:      cells.select { |c| c[:outcome] == "partial" }.sum { |c| c[:count] },
        failed:       cells.select { |c| c[:outcome] == "failed" }.sum { |c| c[:count] },
        input_tokens: tokens,
        cost_cents:   (tokens * CENTS_PER_MTOK / 1_000_000.0).round(3),
        cuisine: {
          calls:      cuisine.sum { |c| c[:count] },
          failed:     cuisine.select { |c| c[:outcome] == "failed" }.sum { |c| c[:count] },
          tagged:     cuisine.sum { |c| c[:tagged] },
          no_cuisine: cuisine.sum { |c| c[:no_cuisine] }
        },
        # `agree` / `disagree` count slices (one row per slice); `jev_only`
        # and `data_only` count dishes. The tile labels say which.
        wheat: {
          calls:     wheat.sum { |c| c[:count] },
          agree:     wheat.select { |c| c[:agree] == true }.sum { |c| c[:count] },
          disagree:  wheat.select { |c| c[:agree] == false }.sum { |c| c[:count] },
          jev_only:  wheat.sum { |c| c[:jev_only] },
          data_only: wheat.sum { |c| c[:data_only] }
        }
      )
    end

    # The queue's per-run rollup, one query for a page of runs, with the
    # empty rollup as the default so a run with no observations serializes
    # the same shape: { run_id => { calls:, failed:, input_tokens:, wheat_jev_only: } }.
    # `wheat_jev_only` is the number this exists to surface: dishes where
    # Jev said wheat and the data said none. The shadow runs only on a
    # run's first attempt, so the sum never counts a dish twice.
    def self.for_runs(run_ids)
      rollup = Hash.new(EMPTY_RUN)
      return rollup if run_ids.empty?

      JevObservation.where(subject_type: "IngestionRun", subject_id: run_ids)
                    .group(:subject_id)
                    .pluck(
                      :subject_id,
                      Arel.sql("COUNT(*)"),
                      Arel.sql("COUNT(*) FILTER (WHERE outcome = 'failed')"),
                      Arel.sql("COALESCE(SUM(input_tokens), 0)"),
                      Arel.sql("COALESCE(SUM(CASE WHEN kind = 'hidden_wheat_shadow' " \
                               "AND jsonb_typeof(details->'jev_only') = 'number' " \
                               "THEN (details->>'jev_only')::integer END), 0)")
                    )
                    .each do |id, calls, failed, tokens, jev_only|
                      rollup[id] = { calls: calls, failed: failed, input_tokens: tokens, wheat_jev_only: jev_only }
                    end
      rollup
    end
  end
end
