require "rails_helper"

RSpec.describe "GET /api/v1/dietary_profiles", type: :request do
  let!(:cheese) { create(:ingredient, slug: "dairy-cheddar") }
  let!(:beef)   { create(:ingredient, slug: "meat-beef") }
  let!(:vegan_tag) { create(:tag, slug: "diet-vegan") }

  let!(:vegan) do
    p = create(:dietary_profile, slug: "vegan")
    create(:dietary_profile_ingredient, dietary_profile: p, ingredient: cheese, rule: "avoid")
    create(:dietary_profile_ingredient, dietary_profile: p, ingredient: beef,   rule: "avoid")
    create(:dietary_profile_tag,        dietary_profile: p, tag: vegan_tag,     rule: "avoid")
    p
  end

  let!(:vegetarian) do
    p = create(:dietary_profile, slug: "vegetarian")
    create(:dietary_profile_ingredient, dietary_profile: p, ingredient: beef, rule: "avoid")
    p
  end

  it "returns presets sorted by name with avoid_*_ids inlined" do
    get "/api/v1/dietary_profiles"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    presets = body["dietary_profiles"]

    expect(presets.length).to eq(2)
    expect(presets.map { |p| p["slug"] }).to eq(%w[vegan vegetarian])

    vegan_payload = presets.find { |p| p["slug"] == "vegan" }
    expect(vegan_payload["avoid_ingredient_ids"]).to contain_exactly(cheese.id, beef.id)
    expect(vegan_payload["avoid_tag_ids"]).to        contain_exactly(vegan_tag.id)
    expect(vegan_payload["name"]).to        be_present
    expect(vegan_payload["description"]).to be_present
  end

  it "is publicly accessible (no auth header required)" do
    get "/api/v1/dietary_profiles"
    expect(response).to have_http_status(:ok)
  end
end
