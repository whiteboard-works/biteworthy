require "swagger_helper"

RSpec.describe "account/export", type: :request do
  path "/api/v1/account/export" do
    get("Export the caller's personal data as a JSON archive (legal E3)") do
      tags "Account"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt>"

      response(200, "the personal-data archive") do
        schema type: :object,
               required: %w[exported_at account profile reviews suggestions restaurant_visits],
               properties: {
                 exported_at: { type: :string, format: "date-time" },
                 account: {
                   type: :object,
                   required: %w[id email handle display_name provider created_at],
                   properties: {
                     id:           { type: :string, format: :uuid },
                     email:        { type: :string },
                     handle:       { type: :string },
                     display_name: { type: :string, nullable: true },
                     provider:     { type: :string, nullable: true },
                     created_at:   { type: :string, format: "date-time" }
                   }
                 },
                 profile: { type: :object, nullable: true },
                 reviews: { type: :array, items: { type: :object } },
                 suggestions: { type: :array, items: { type: :object } },
                 restaurant_visits: { type: :array, items: { type: :object } }
               }

        let(:account) { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end

        let!(:review)     { create(:review, user: account, body: "Loved it") }
        let!(:suggestion) { create(:item_suggestion_pending, user: account) }
        let!(:visit)      { create(:restaurant_visit, user: account) }
        # A record belonging to someone else must never leak into the export.
        let!(:other_review) { create(:review, body: "Not mine") }

        run_test! do |response|
          json = JSON.parse(response.body)
          expect(json["account"]["id"]).to eq(account.id)
          expect(json["account"]["email"]).to eq(account.email)
          expect(json["reviews"].map { |r| r["id"] }).to contain_exactly(review.id)
          expect(json["reviews"].first["body"]).to eq("Loved it")
          expect(json["suggestions"].map { |s| s["id"] }).to contain_exactly(suggestion.id)
          expect(json["restaurant_visits"].map { |v| v["id"] }).to contain_exactly(visit.id)
          expect(json["profile"]).to include("strictness", "avoid_ingredient_ids")
          # No password hash, no JWT secret — only the user's own data.
          expect(response.body).not_to include("encrypted_password")
        end
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        run_test!
      end
    end
  end
end
