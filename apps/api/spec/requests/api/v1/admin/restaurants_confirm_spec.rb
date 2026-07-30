require "rails_helper"

# Confirm-community is the strict-mode graduation lever: it's how
# community-scanned data becomes visible to allergy users. The
# endpoint must report exactly what it flipped, must not graduate an
# item still carrying an ai-suggested join (strict mode would show it
# while an untrusted association remains), and must be idempotent.
RSpec.describe "Admin restaurant confirm_community", type: :request do
  let(:admin)      { create(:user, :admin) }
  let(:restaurant) { create(:restaurant, :published) }

  it "flips suggested human joins to confirmed, graduates clean items, and reports counts" do
    clean = create(:item, restaurant: restaurant, confidence: "suggested")
    tainted = create(:item, restaurant: restaurant, confidence: "suggested")
    ing = create(:ingredient)
    ItemIngredient.create!(item: clean,   ingredient: ing, confidence: "suggested", source: "human")
    ItemIngredient.create!(item: tainted, ingredient: ing, confidence: "suggested", source: "ai")

    post "/api/v1/admin/restaurants/#{restaurant.id}/confirm_community",
         headers: auth_headers_for(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "restaurant_id" => restaurant.id,
      "confirmed" => { "items" => 1, "ingredients" => 1, "tags" => 0 }
    )
    expect(clean.reload.confidence).to eq("confirmed")
    # The ai-sourced join was untouched and keeps its item out of strict mode.
    expect(tainted.reload.confidence).to eq("suggested")

    # Idempotent: a second call flips nothing.
    post "/api/v1/admin/restaurants/#{restaurant.id}/confirm_community",
         headers: auth_headers_for(admin)
    expect(response.parsed_body["confirmed"]).to eq("items" => 0, "ingredients" => 0, "tags" => 0)
  end

  it "404s non-admins and unknown restaurants alike" do
    post "/api/v1/admin/restaurants/#{restaurant.id}/confirm_community",
         headers: auth_headers_for(create(:user))
    expect(response).to have_http_status(:not_found)

    post "/api/v1/admin/restaurants/00000000-0000-0000-0000-000000000000/confirm_community",
         headers: auth_headers_for(admin)
    expect(response).to have_http_status(:not_found)
  end
end
