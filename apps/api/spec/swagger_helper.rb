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
          ProfilePayload: {
            type: :object,
            required: %w[avoid_ingredient_ids avoid_tag_ids prefer_tag_ids strictness primary_dietary_profile],
            properties: {
              avoid_ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
              avoid_tag_ids:        { type: :array, items: { type: :string, format: :uuid } },
              prefer_tag_ids:       { type: :array, items: { type: :string, format: :uuid } },
              strictness:           { type: :string, enum: %w[relaxed balanced strict] },
              primary_dietary_profile: {
                type: :object, nullable: true,
                properties: {
                  id:   { type: :string, format: :uuid },
                  slug: { type: :string },
                  name: { type: :string }
                }
              }
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
