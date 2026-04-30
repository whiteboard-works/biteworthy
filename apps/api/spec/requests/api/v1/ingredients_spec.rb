require "rails_helper"

RSpec.describe "GET /api/v1/ingredients", type: :request do
  let!(:cheddar)   { create(:ingredient, slug: "dairy-cheddar") }
  let!(:beef)      { create(:ingredient, slug: "meat-beef") }
  let!(:cilantro)  { create(:ingredient, slug: "herb-cilantro") }
  let!(:salmon)    { create(:ingredient, slug: "fish-salmon") }

  it "returns up to DEFAULT_LIMIT ingredients without ?q=" do
    get "/api/v1/ingredients"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["ingredients"]).to be_an(Array)
    expect(body["ingredients"].size).to be <= 20
    expect(body["ingredients"].first.keys).to include(
      "id", "slug", "name", "path", "aliases", "allergen"
    )
  end

  it "filters by ?q= via name ILIKE" do
    get "/api/v1/ingredients?q=Cheddar"

    expect(response).to have_http_status(:ok)
    slugs = response.parsed_body["ingredients"].map { |i| i["slug"] }
    expect(slugs).to include("dairy-cheddar")
    expect(slugs).not_to include("meat-beef")
  end

  it "filters by alias too (the 'garbanzo' / 'chickpea' use case)" do
    create(:ingredient, slug: "legume-chickpeas", name: "Chickpea", aliases: %w[garbanzo])

    get "/api/v1/ingredients?q=garbanzo"

    expect(response).to have_http_status(:ok)
    slugs = response.parsed_body["ingredients"].map { |i| i["slug"] }
    expect(slugs).to include("legume-chickpeas")
  end

  it "respects ?limit= up to MAX_LIMIT" do
    get "/api/v1/ingredients?limit=2"

    expect(response.parsed_body["ingredients"].size).to be <= 2
  end

  it "is publicly accessible (no auth required)" do
    get "/api/v1/ingredients"
    expect(response).to have_http_status(:ok)
  end
end
