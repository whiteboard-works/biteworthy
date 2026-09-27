require "swagger_helper"

RSpec.describe "admin/cities", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/admin/cities" do
    post("Add a city") do
      tags "Admin"
      description "Creates a city restaurants can be added to. The slug is derived from the " \
                  "name and is permanent. 409 with the existing city when it is already covered."
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[name region],
        properties: {
          name:   { type: :string },
          region: { type: :string, description: "US state name or two-letter code; stored as the name" }
        }
      }

      response(201, "created") do
        schema "$ref" => "#/components/schemas/City"
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:body) { { name: "Salt Lake City", region: "ut" } }

        run_test! do |response|
          expect(JSON.parse(response.body)).to include("slug" => "salt-lake-city", "region" => "Utah")
        end
      end

      response(409, "already covered") do
        schema type: :object,
               required: %w[error city],
               properties: { error: { type: :string }, city: { "$ref" => "#/components/schemas/City" } }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:body) { { name: "Salt Lake City", region: "UT" } }
        before { create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "Utah") }
        run_test!
      end

      response(422, "region is not a US state") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:body) { { name: "Salt Lake City", region: "Utha" } }
        run_test!
      end

      response(401, "not signed in") do
        let(:Authorization) { "Bearer invalid" }
        let(:body) { { name: "Salt Lake City", region: "UT" } }
        run_test!
      end

            response(404, "not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:body) { { name: "Salt Lake City", region: "UT" } }

        run_test! { expect(City.count).to eq(0) }
      end
    end
  end
end
