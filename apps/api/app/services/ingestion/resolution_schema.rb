# frozen_string_literal: true

# JSON Schema for the structured output returned by both
# `ResolveIngredientsJob` and `ResolveTagsJob`. Anthropic returns one
# array entry per item we asked it to resolve (in the same order),
# carrying the resolved-slug list and the unresolved-string list.
module Ingestion
  ResolutionSchema = {
    type: "object",
    required: ["items"],
    additionalProperties: false,
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          required: %w[index resolved unresolved],
          additionalProperties: false,
          properties: {
            index: { type: "integer", minimum: 0 },
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
        }
      }
    }
  }.freeze
end
