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
end
