# frozen_string_literal: true

# Phase 6.1.1 — turns an Anthropic `usage` object into cents so
# IngestionRun.api_cost_cents reflects real spend (the Phase 6.1 daily
# cost ceiling and the Phase 2.9 dashboard both read that column).
#
# Pricing is cents per million tokens, from the published rate card
# (claude-sonnet-4-6: $3/MTok input, $15/MTok output; prompt-cache
# reads bill at 0.1x input, 5-minute-TTL cache writes at 1.25x input).
# Unknown models fall back to the default model's pricing — wrong-ish
# beats zero for a spend guardrail.
#
# Per-call costs round UP to the next cent. Sub-cent resolve calls
# would otherwise round to zero and the ceiling would leak; for a
# guardrail, overstating by <1 cent per call is the safe direction.
module Ingestion
  class UsageCost
    CENTS_PER_MTOK = {
      "claude-sonnet-4-6" => {
        input:       300,
        output:      1_500,
        cache_read:  30,
        cache_write: 375
      },
      # claude-haiku-4-5: $1/MTok input, $5/MTok output (cache read 0.1x
      # input, cache write 1.25x). Used by the resolve stages.
      "claude-haiku-4-5-20251001" => {
        input:       100,
        output:      500,
        cache_read:  10,
        cache_write: 125
      }
    }.freeze

    def self.cents(usage, model: AnthropicClient::DEFAULT_MODEL)
      return 0 if usage.blank?

      rates = CENTS_PER_MTOK.fetch(model, CENTS_PER_MTOK.fetch(AnthropicClient::DEFAULT_MODEL))
      raw = (usage["input_tokens"].to_i          * rates[:input]) +
            (usage["output_tokens"].to_i         * rates[:output]) +
            (usage["cache_read_input_tokens"].to_i     * rates[:cache_read]) +
            (usage["cache_creation_input_tokens"].to_i * rates[:cache_write])
      (raw / 1_000_000.0).ceil
    end
  end
end
