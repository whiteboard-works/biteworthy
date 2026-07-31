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
          }
        },
        schemas: {
          Error: {
            type: :object,
            properties: {
              error: { type: :string }
            }
          },
          Pagination: {
            type: :object,
            required: %w[total limit offset],
            properties: {
              total:  { type: :integer },
              limit:  { type: :integer },
              offset: { type: :integer }
            }
          },
          # The IngestionItemsController serialization — shared by the
          # items index, single-item PATCH, and accept_all responses.
          IngestionItemPayload: {
            type: :object,
            required: %w[id ingestion_run_id name decision],
            properties: {
              id:               { type: :string, format: :uuid },
              ingestion_run_id: { type: :string, format: :uuid },
              item_id:          { type: :string, format: :uuid, nullable: true },
              position:         { type: :integer, nullable: true },
              name:             { type: :string },
              description:      { type: :string, nullable: true },
              section_name:     { type: :string, nullable: true },
              decision:         { type: :string, enum: %w[pending accepted rejected edited] },
              decided_at:       { type: :string, format: "date-time", nullable: true },
              # Payload row shapes. Promote reads ingredients/tags by `slug`
              # only (the extractor's per-row `confidence` float is advisory);
              # prices need `price_cents` (a size with no price is dropped).
              ingredients_payload: {
                type: :array,
                items: {
                  type: :object,
                  required: %w[slug],
                  properties: {
                    slug:       { type: :string },
                    confidence: { type: :number },
                    source:     { type: :string }
                  }
                }
              },
              tags_payload: {
                type: :array,
                items: {
                  type: :object,
                  required: %w[slug],
                  properties: {
                    slug:       { type: :string },
                    confidence: { type: :number },
                    source:     { type: :string }
                  }
                }
              },
              prices_payload: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    size:        { type: :string, nullable: true },
                    price_cents: { type: :integer, nullable: true }
                  }
                }
              },
              addons_payload: {
                type: :array,
                items: {
                  type: :object,
                  required: %w[name],
                  properties: {
                    name:        { type: :string },
                    price_cents: { type: :integer, nullable: true },
                    # "extract"/"guard" from the pipeline, but an edit can
                    # store any source string — don't enum a read field
                    # the write side leaves open.
                    source:      { type: :string }
                  }
                }
              },
              unresolved_ingredients: { type: :array, items: { type: :string } },
              unresolved_tags:        { type: :array, items: { type: :string } },
              # Re-scan dedup: present when this staged row matched an
              # existing Item (diff computed at serialize time).
              match: {
                type: :object, nullable: true,
                properties: {
                  item_id: { type: :string, format: :uuid },
                  score:   { type: :number, nullable: true },
                  existing: {
                    type: :object,
                    properties: {
                      name:        { type: :string },
                      description: { type: :string, nullable: true },
                      prices: { type: :array, items: { type: :object, additionalProperties: true } }
                    }
                  },
                  diff:       { type: :object, additionalProperties: true },
                  no_changes: { type: :boolean }
                }
              }
            }
          },
          # The IngestionRunsController#serialize_run shape (run show).
          IngestionRunPayload: {
            type: :object,
            required: %w[id status restaurant_id],
            properties: {
              id:                { type: :string, format: :uuid },
              status:            { type: :string, enum: %w[queued extracting resolving staged published failed] },
              enrichment_status: { type: :string, enum: %w[pending completed failed] },
              input_kind:        { type: :string, enum: %w[photo url pdf text] },
              restaurant_id:     { type: :string, format: :uuid, nullable: true },
              state_history:     { type: :object, additionalProperties: true },
              failure_message:   { type: :string, nullable: true },
              api_cost_cents:    { type: :integer, nullable: true },
              latency_ms:        { type: :integer, nullable: true },
              input_count:       { type: :integer },
              ingestion_items_count: { type: :integer },
              created_at:        { type: :string, format: "date-time" },
              updated_at:        { type: :string, format: "date-time" }
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
            required: %w[id email handle is_admin],
            properties: {
              id:           { type: :string, format: :uuid },
              email:        { type: :string, format: :email },
              handle:       { type: :string },
              display_name: { type: :string, nullable: true },
              is_admin:     { type: :boolean },
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
                         avoid_ingredients avoid_tags
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
