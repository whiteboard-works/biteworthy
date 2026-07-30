require "swagger_helper"

RSpec.describe "admin/dashboard", type: :request do
  path "/api/v1/admin/dashboard" do
    get("Ops dashboard: ingestion cost metrics, community spend, queue counts") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"

      response(200, "metrics buckets + community counters + queue counts") do
        period_bucket = {
          type: :object,
          required: %w[label run_count item_count total_cost_cents
                       cost_per_item_cents cache_hit_rate],
          properties: {
            label:               { type: :string },
            run_count:           { type: :integer },
            item_count:          { type: :integer },
            total_cost_cents:    { type: :integer },
            cost_per_item_cents: { type: :number },
            avg_latency_ms:      { type: :integer, nullable: true },
            p95_latency_ms:      { type: :integer, nullable: true },
            cache_hit_rate:      { type: :number }
          }
        }

        schema type: :object,
               required: %w[target_cents_per_item periods community queues],
               properties: {
                 target_cents_per_item: { type: :number },
                 periods: {
                   type: :object,
                   required: %w[today last_7_days last_30_days],
                   properties: {
                     today:        period_bucket,
                     last_7_days:  period_bucket,
                     last_30_days: period_bucket
                   }
                 },
                 community: {
                   type: :object,
                   required: %w[runs_today spend_today_cents ceiling_cents],
                   properties: {
                     runs_today:        { type: :integer },
                     spend_today_cents: { type: :integer },
                     ceiling_cents:     { type: :integer }
                   }
                 },
                 queues: {
                   type: :object,
                   required: %w[flagged_reviews pending_suggestions
                                community_published_restaurants staged_runs],
                   properties: {
                     flagged_reviews:                 { type: :integer },
                     pending_suggestions:             { type: :integer },
                     community_published_restaurants: { type: :integer },
                     staged_runs:                     { type: :integer }
                   }
                 }
               }

        let(:account) { create(:user, :admin) }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        run_test!
      end

      # The admin namespace's gate contract: authenticated non-admins
      # get 404, never 403 — the namespace's existence is not
      # advertised to probing.
      response(404, "authenticated but not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:account) { create(:user) }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        run_test!
      end
    end
  end
end
