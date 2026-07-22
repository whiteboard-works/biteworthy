# frozen_string_literal: true

require "rails_helper"

# rswag generates the OpenAPI document by walking every spec under
# `spec/integration/**/*_spec.rb` that uses the rswag DSL. The output
# goes straight into the repo-root `docs/openapi.json` so the JS-side
# codegen (`pnpm --filter @biteworthy/api-types build:codegen`) can
# read it without needing to know about `apps/api`'s internal layout.
RSpec.configure do |config|
  config.openapi_root = Rails.root.join("../../docs").to_s

  config.openapi_specs = {
    "openapi.json" => {
      openapi: "3.0.3",
      info: {
        title: "BiteWorthy API",
        version: "v1",
        description: "JSON API for the BiteWorthy v2 product. Generated from rswag specs."
      },
      paths: {},
      servers: [
        { url: "http://localhost:3000", description: "Local dev" },
        { url: "https://api.biteworthy.app", description: "Production (planned)" }
      ],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: "JWT",
            description: "Authorization: Bearer <jwt> — minted by signup/login/refresh."
          },
          basicAuth: {
            type: :http,
            scheme: :basic,
            description: "HTTP Basic — only used for /admin (Avo)."
          }
        },
        schemas: {
          Error: {
            type: :object,
            properties: {
              error: { type: :string }
            }
          },
          ValidationErrors: {
            type: :object,
            properties: {
              errors: {
                type: :object,
                additionalProperties: { type: :array, items: { type: :string } }
              }
            }
          },
          UserPayload: {
            type: :object,
            required: %w[id email handle],
            properties: {
              id:           { type: :string, format: :uuid },
              email:        { type: :string, format: :email },
              handle:       { type: :string },
              display_name: { type: :string, nullable: true },
              provider:     { type: :string, nullable: true,
                              enum: %w[google_oauth2 apple] }
            }
          },
          AuthResponse: {
            type: :object,
            required: %w[user],
            properties: {
              user: { "$ref" => "#/components/schemas/UserPayload" }
            }
          },
          IngredientRef: {
            type: :object,
            required: %w[id slug name],
            properties: {
              id:   { type: :string, format: :uuid },
              slug: { type: :string },
              name: { type: :string }
            }
          },
          TagRef: {
            type: :object,
            required: %w[id slug name family],
            properties: {
              id:     { type: :string, format: :uuid },
              slug:   { type: :string },
              name:   { type: :string },
              family: { type: :string, enum: %w[diet allergen cuisine prep flavor] }
            }
          },
          ProfilePayload: {
            type: :object,
            required: %w[avoid_ingredient_ids avoid_tag_ids prefer_tag_ids
                         liked_ingredient_ids liked_tag_ids
                         disliked_ingredient_ids disliked_tag_ids
                         avoid_ingredients avoid_tags prefer_tags
                         liked_ingredients liked_tags
                         disliked_ingredients disliked_tags
                         strictness primary_dietary_profile
                         disclaimer_acknowledged_at],
            properties: {
              avoid_ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
              avoid_tag_ids:        { type: :array, items: { type: :string, format: :uuid } },
              prefer_tag_ids:       { type: :array, items: { type: :string, format: :uuid } },
              # Phase 8.1 — taste signals: soft preferences that rank
              # Top Picks. Never hide items (avoid arrays do that).
              liked_ingredient_ids:    { type: :array, items: { type: :string, format: :uuid } },
              liked_tag_ids:           { type: :array, items: { type: :string, format: :uuid } },
              disliked_ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
              disliked_tag_ids:        { type: :array, items: { type: :string, format: :uuid } },
              # Resolved {id, slug, name(, family)} rows for each id array
              # above — the account page renders these without a second
              # ingredient/tag lookup. Stale ids drop out.
              avoid_ingredients:    { type: :array, items: { "$ref" => "#/components/schemas/IngredientRef" } },
              avoid_tags:           { type: :array, items: { "$ref" => "#/components/schemas/TagRef" } },
              prefer_tags:          { type: :array, items: { "$ref" => "#/components/schemas/TagRef" } },
              liked_ingredients:    { type: :array, items: { "$ref" => "#/components/schemas/IngredientRef" } },
              liked_tags:           { type: :array, items: { "$ref" => "#/components/schemas/TagRef" } },
              disliked_ingredients: { type: :array, items: { "$ref" => "#/components/schemas/IngredientRef" } },
              disliked_tags:        { type: :array, items: { "$ref" => "#/components/schemas/TagRef" } },
              strictness:           { type: :string, enum: %w[relaxed balanced strict] },
              primary_dietary_profile: {
                type: :object, nullable: true,
                properties: {
                  id:   { type: :string, format: :uuid },
                  slug: { type: :string },
                  name: { type: :string }
                }
              },
              # Legal remediation E1 — ISO-8601 timestamp of when the
              # user accepted the in-app allergen disclaimer, or null if
              # they never have. Server-stamped.
              disclaimer_acknowledged_at: { type: :string, format: "date-time", nullable: true }
            }
          }
        }
      }
    }
  }

  # JSON, not YAML — openapi-typescript prefers JSON and the diff
  # noise is lower since the generator keeps key order stable.
  config.openapi_format = :json
end
