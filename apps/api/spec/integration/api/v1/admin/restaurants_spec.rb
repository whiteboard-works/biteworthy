require "swagger_helper"

RSpec.describe "admin/restaurants", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/admin/restaurants/{id}/confirm_community" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post("Graduate community data to strict-mode visibility") do
      tags "Admin"
      description "Flips the restaurant's suggested human-sourced joins to confirmed, " \
                  "then graduates items whose every association is confirmed. Idempotent."
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"

      response(200, "counts of rows flipped by this call") do
        schema type: :object,
               required: %w[restaurant_id confirmed],
               properties: {
                 restaurant_id: { type: :string, format: :uuid },
                 confirmed: {
                   type: :object,
                   required: %w[items ingredients tags],
                   properties: {
                     items:       { type: :integer },
                     ingredients: { type: :integer },
                     tags:        { type: :integer }
                   }
                 }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:restaurant, :published).id }
        run_test!
      end

      response(404, "not an admin, or unknown restaurant") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:id) { create(:restaurant, :published).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/restaurants/{id}/backfill_structure" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post("Backfill sections, prices, and optional source-menu order") do
      tags "Admin"
      description "Rebuilds missing menu sections and item variants from accepted " \
                  "ingestion payloads. Defaults to dry_run — send dry_run=false to write. " \
                  "reorder=true rewrites menu_sections.position and items.position from " \
                  "source-menu order (latest accepted ingestion item per dish) without " \
                  "moving a dish or creating/renaming sections. Unsourced sections stay " \
                  "after sourced ones in their current relative order."
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"
      parameter name: :dry_run, in: :query, type: :boolean, required: false,
                description: "Preview only. Defaults to true; send false to persist."
      parameter name: :reorder, in: :query, type: :boolean, required: false,
                description: "Rewrite section and item positions from source-menu order."
      parameter name: :overwrite_prices, in: :query, type: :boolean, required: false,
                description: "Replace existing item variants from the latest accepted prices."

      response(200, "backfill preview or applied changes") do
        schema type: :object,
               required: %w[restaurant_id dry_run reorder sections_created variants_added
                            sections_reordered items_reordered],
               properties: {
                 restaurant_id: { type: :string, format: :uuid },
                 dry_run: { type: :boolean },
                 reorder: { type: :boolean },
                 sections_created: { type: :array, items: { type: :object } },
                 variants_added: { type: :array, items: { type: :object } },
                 sections_reordered: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :string, format: :uuid },
                       name: { type: :string },
                       old_position: { type: :integer },
                       new_position: { type: :integer }
                     }
                   }
                 },
                 items_reordered: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :string, format: :uuid },
                       name: { type: :string },
                       section_id: { type: :string, format: :uuid },
                       old_position: { type: :integer },
                       new_position: { type: :integer }
                     }
                   }
                 }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:restaurant, :published).id }
        let(:reorder) { true }
        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["dry_run"]).to eq(true)
          expect(body["reorder"]).to eq(true)
          expect(body["sections_reordered"]).to eq([])
          expect(body["items_reordered"]).to eq([])
        end
      end

      response(404, "not an admin, or unknown restaurant") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:id) { create(:restaurant, :published).id }
        run_test!
      end
    end
  end
end
