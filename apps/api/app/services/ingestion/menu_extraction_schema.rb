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
                  },
                  # Phase 4.11.2 — optional per-dish bounding box for the
                  # cropper (Phase 4.11.1 + 4.11.3). Coordinates are
                  # fractions of the source page so resolution-independent:
                  # 0,0 = top-left, 1,1 = bottom-right; w + h are the
                  # box's width + height as fractions. Items without an
                  # inline photo on the source page should omit this
                  # field entirely. The `oneOf` shape is draft-04-safe
                  # (json-schema gem default): a union type at the top
                  # level dilutes the sub-object rules, so we
                  # explicitly enumerate "null" + "fully-typed object."
                  # `exclusiveMinimum: true` (boolean form) goes with
                  # `minimum: 0` for w/h since draft-04 doesn't support
                  # the numeric `exclusiveMinimum` form.
                  image_bbox: {
                    oneOf: [
                      { type: "null" },
                      {
                        type: "object",
                        required: %w[x y w h],
                        additionalProperties: false,
                        properties: {
                          x: { type: "number", minimum: 0, maximum: 1 },
                          y: { type: "number", minimum: 0, maximum: 1 },
                          w: { type: "number", minimum: 0, exclusiveMinimum: true, maximum: 1 },
                          h: { type: "number", minimum: 0, exclusiveMinimum: true, maximum: 1 }
                        }
                      }
                    ]
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
