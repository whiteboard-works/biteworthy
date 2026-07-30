# frozen_string_literal: true

# JSON Schema for the gap-fill enrichment call. One entry per gap item,
# carrying ADDITIONS only: implied ingredients and cuisine tags. There
# is deliberately no field for allergen/diet/prep/flavor tags — those
# families are derived in code (TagDeriver) and never asked of the LLM.
module Ingestion
  resolution = {
    type: "object",
    required: %w[resolved unresolved],
    additionalProperties: false,
    properties: {
      resolved: {
        type: "array",
        items: {
          type: "object",
          required: %w[slug confidence],
          additionalProperties: false,
          properties: {
            slug:       { type: "string", minLength: 1 },
            confidence: { type: "number", minimum: 0, maximum: 1 }
          }
        }
      },
      unresolved: {
        type: "array",
        items: { type: "string", minLength: 1 }
      }
    }
  }.freeze

  GapFillSchema = {
    type: "object",
    required: ["items"],
    additionalProperties: false,
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          required: %w[index ingredients cuisine_tags],
          additionalProperties: false,
          properties: {
            index:        { type: "integer", minimum: 0 },
            ingredients:  resolution,
            cuisine_tags: resolution
          }
        }
      }
    }
  }.freeze
end
