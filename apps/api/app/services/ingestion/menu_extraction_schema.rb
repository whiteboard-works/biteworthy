# frozen_string_literal: true

# JSON Schema for the structured output Anthropic returns when asked
# to extract a menu. Validates exactly the shape that gets written to
# `IngestionRun#staging`. Phase 2.4's resolve jobs read from this
# shape, so schema changes here ripple downstream.
#
# Mirrors the example in docs/ingestion.md:
#
#   {
#     "sections": [
#       {
#         "name": "Tacos",
#         "items": [
#           { "name": "Carne Asada Taco",
#             "description": "Grilled steak, cilantro, onion, lime.",
#             "prices": [{ "size": null, "price_cents": 450 }] }
#         ]
#       }
#     ]
#   }
module Ingestion
  MenuExtractionSchema = {
    type: "object",
    required: ["sections"],
    additionalProperties: false,
    properties: {
      sections: {
        type: "array",
        items: {
          type: "object",
          required: %w[name items],
          additionalProperties: false,
          properties: {
            name:  { type: "string", minLength: 1 },
            items: {
              type: "array",
              items: {
                type: "object",
                required: ["name"],
                additionalProperties: false,
                properties: {
                  name:        { type: "string", minLength: 1 },
                  description: { type: %w[string null] },
                  prices: {
                    type: "array",
                    items: {
                      type: "object",
                      required: %w[size price_cents],
                      additionalProperties: false,
                      properties: {
                        size:        { type: %w[string null] },
                        price_cents: { type: %w[integer null], minimum: 0 }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }.freeze
end
