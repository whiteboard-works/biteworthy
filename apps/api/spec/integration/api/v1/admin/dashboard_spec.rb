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

        jev_bucket = {
          type: :object,
          required: %w[label calls answered partial failed input_tokens cost_cents cuisine wheat],
          properties: {
            label:        { type: :string },
            calls:        { type: :integer },
            answered:     { type: :integer },
            partial:      { type: :integer },
            failed:       { type: :integer },
            input_tokens: { type: :integer },
            cost_cents:   { type: :number },
            cuisine: {
              type: :object,
              required: %w[calls failed tagged no_cuisine],
              properties: {
                calls: { type: :integer }, failed: { type: :integer },
                tagged: { type: :integer }, no_cuisine: { type: :integer }
              }
            },
            wheat: {
              type: :object,
              required: %w[calls agree disagree jev_only data_only],
              properties: {
                calls: { type: :integer }, agree: { type: :integer }, disagree: { type: :integer },
                jev_only: { type: :integer }, data_only: { type: :integer }
              }
            }
          }
        }

        schema type: :object,
               required: %w[target_cents_per_item periods jev community queues],
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
                 jev: {
                   type: :object,
                   required: %w[today last_7_days last_30_days],
                   properties: {
                     today:        jev_bucket,
                     last_7_days:  jev_bucket,
                     last_30_days: jev_bucket
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
                                community_published_restaurants staged_runs
                                pending_photo_submissions],
                   properties: {
                     flagged_reviews:                 { type: :integer },
                     pending_suggestions:             { type: :integer },
                     community_published_restaurants: { type: :integer },
                     staged_runs:                     { type: :integer },
                     pending_photo_submissions:       { type: :integer }
                   }
                 }
               }

        let(:account) { create(:user, :admin) }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        before do
          run = create(:ingestion_run, :staged)
          JevObservation.note(kind: "cuisine", subject: run, outcome: "answered", input_tokens: 2_000,
                              details: { items: 10, tagged: 7, no_cuisine: 2, missing: 0 })
          JevObservation.note(kind: "hidden_wheat_shadow", subject: run, outcome: "answered", agree: false,
                              input_tokens: 500, details: { items: 10, agree: 9, jev_only: 1, data_only: 0 })
        end
        run_test! do |response|
          today = JSON.parse(response.body).dig("jev", "today")
          expect(today).to include("calls" => 2, "answered" => 2, "input_tokens" => 2_500)
          expect(today["cuisine"]).to include("tagged" => 7, "no_cuisine" => 2)
          expect(today["wheat"]).to include("disagree" => 1, "jev_only" => 1)
        end
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
