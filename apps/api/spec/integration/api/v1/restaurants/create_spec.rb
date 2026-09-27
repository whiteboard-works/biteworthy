require "swagger_helper"

RSpec.describe "restaurants", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  let(:user) { create(:user) }
  let!(:city) { create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "Utah") }

  path "/api/v1/restaurants" do
    get("List published restaurants") do
      tags "Restaurants"
      description "Public. Name-ordered, capped at 100; `q` is a case-insensitive name match."
      produces "application/json"
      parameter name: :q, in: :query, type: :string, required: false

      response(200, "published restaurants") do
        schema type: :object,
               required: %w[restaurants],
               properties: {
                 restaurants: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id slug name status city street latitude longitude],
                     properties: {
                       id:        { type: :string, format: :uuid },
                       slug:      { type: :string },
                       name:      { type: :string },
                       status:    { type: :string },
                       street:    { type: :string, nullable: true },
                       latitude:  { type: :number, nullable: true },
                       longitude: { type: :number, nullable: true },
                       city: {
                         type: :object,
                         required: %w[slug name],
                         properties: {
                           slug:   { type: :string },
                           name:   { type: :string },
                           region: { type: :string, nullable: true }
                         }
                       }
                     }
                   }
                 }
               }
        let(:q) { "iguana" }
        before do
          create(:restaurant, :published, name: "Red Iguana", slug: "red-iguana", city: city)
          create(:restaurant, name: "Draft Iguana", slug: "draft-iguana", city: city)
        end

        run_test! do |response|
          expect(JSON.parse(response.body)["restaurants"].map { |r| r["slug"] }).to eq([ "red-iguana" ])
        end
      end
    end

    post("Add a restaurant we don't have yet") do
      tags "Restaurants"
      description "Creates a DRAFT restaurant attributed to the caller. A likely duplicate in the " \
                  "same city answers 409 with candidates; `scannable` says whether the caller " \
                  "could scan each one. Send `force: true` once they have ruled the candidates out."
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[name city_slug],
        properties: {
          name:        { type: :string },
          city_slug:   { type: :string },
          street:      { type: :string },
          postal_code: { type: :string },
          force:       { type: :boolean }
        }
      }

      response(201, "created as a draft") do
        schema type: :object,
               required: %w[id slug name status city],
               properties: {
                 id:     { type: :string, format: :uuid },
                 slug:   { type: :string },
                 name:   { type: :string },
                 status: { type: :string },
                 city:   {
                   type: :object,
                   required: %w[id slug name],
                   properties: {
                     id:     { type: :string, format: :uuid },
                     slug:   { type: :string },
                     name:   { type: :string },
                     region: { type: :string, nullable: true }
                   }
                 }
               }
        let(:Authorization) { bearer_for(user) }
        let(:body) { { name: "Red Iguana", city_slug: "salt-lake-city" } }

        run_test! { |response| expect(JSON.parse(response.body)["status"]).to eq("draft") }
      end

      response(409, "likely duplicate; nothing created") do
        schema type: :object,
               required: %w[error candidates],
               properties: {
                 error:      { type: :string },
                 candidates: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id slug name status scannable],
                     properties: {
                       id:        { type: :string, format: :uuid },
                       slug:      { type: :string },
                       name:      { type: :string },
                       status:    { type: :string },
                       street:    { type: :string, nullable: true },
                       scannable: { type: :boolean }
                     }
                   }
                 }
               }
        let(:Authorization) { bearer_for(user) }
        let(:body) { { name: "Red Iguana 2", city_slug: "salt-lake-city" } }
        before { create(:restaurant, :published, name: "Red Iguana", slug: "red-iguana", city: city) }

        run_test! do |response|
          expect(JSON.parse(response.body)["candidates"].sole).to include("slug" => "red-iguana", "scannable" => true)
        end
      end

      response(401, "not signed in") do
        let(:Authorization) { "Bearer invalid" }
        let(:body) { { name: "Red Iguana", city_slug: "salt-lake-city" } }
        run_test!
      end

      response(422, "blank name") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(user) }
        let(:body) { { name: "  ", city_slug: "salt-lake-city" } }
        run_test!
      end

      response(404, "unknown city") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(user) }
        let(:body) { { name: "Red Iguana", city_slug: "atlantis" } }
        run_test!
      end
    end
  end
end
