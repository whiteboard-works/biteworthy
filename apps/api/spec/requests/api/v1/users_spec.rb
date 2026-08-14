require "rails_helper"

RSpec.describe "GET /api/v1/users/:handle", type: :request do
  let(:user)       { create(:user, handle: "diner_jane", display_name: "Diner Jane") }
  let(:restaurant) { create(:restaurant, :published, name: "Ninis Taqueria") }
  let(:item)       { create(:item, :published, restaurant: restaurant, name: "Pollo Taco") }

  it "returns the public payload — anonymously" do
    create(:review, user: user, item: item, rating: 5, body: "Great.")

    get "/api/v1/users/#{user.handle}"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body

    expect(body).to include(
      "handle"       => "diner_jane",
      "display_name" => "Diner Jane",
      "reviews_count" => 1,
      "restaurants_reviewed_count" => 1
    )
    expect(body["member_since"]).to be_present
    expect(body["recent_reviews"].length).to eq(1)

    review = body["recent_reviews"].first
    expect(review).to include("rating" => 5, "body" => "Great.")
    expect(review["item"]).to include(
      "id"   => item.id,
      "name" => "Pollo Taco"
    )
    expect(review["item"]["restaurant"]).to include(
      "slug" => restaurant.slug,
      "name" => "Ninis Taqueria"
    )
  end

  it "never leaks sensitive fields (no email, no dietary profile, no jti)" do
    create(:review, user: user, item: item, rating: 5)

    get "/api/v1/users/#{user.handle}"

    body = response.parsed_body
    expect(body.keys).to contain_exactly(
      "handle", "display_name", "member_since",
      "reviews_count", "restaurants_reviewed_count", "recent_reviews"
    )
    serialized = response.body
    [user.email, user.jti].each do |secret|
      expect(serialized).not_to include(secret), "leaked #{secret}"
    end
  end

  # Legal remediation E13 — the dietary profile is special-category
  # health data and must NEVER appear in the public profile response.
  # The "no email/jti" test above uses an empty profile, so it couldn't
  # catch a real leak; this one POPULATES every dietary field with a
  # sentinel value and asserts none of them — keys or values — escape.
  it "never exposes the dietary profile, even when fully populated" do
    liked_ingredient = create(:ingredient)
    liked_tag        = create(:tag)
    # Real rows rather than sentinel UUIDs: the avoid lists validate that
    # their ids resolve, the same as the taste fields beside them. The id
    # is still the needle this example greps the response for — it just
    # has to be an id something actually has.
    avoid_ingredient = create(:ingredient).id
    avoid_tag        = create(:tag).id

    user.profile.update!(
      strictness:            "strict",
      avoid_ingredient_ids:  [avoid_ingredient],
      avoid_tag_ids:         [avoid_tag],
      liked_ingredient_ids:  [liked_ingredient.id],
      liked_tag_ids:         [liked_tag.id]
    )
    create(:review, user: user, item: item, rating: 5)

    get "/api/v1/users/#{user.handle}"
    expect(response).to have_http_status(:ok)

    # No dietary field NAME appears anywhere in the payload (recursive).
    dietary_keys = %w[
      strictness avoid_ingredient_ids avoid_tag_ids prefer_tag_ids
      liked_ingredient_ids liked_tag_ids disliked_ingredient_ids
      disliked_tag_ids primary_dietary_profile
    ]
    all_keys = deep_keys(response.parsed_body)
    expect(all_keys & dietary_keys).to be_empty,
      "public payload exposed dietary key(s): #{(all_keys & dietary_keys).inspect}"

    # No dietary VALUE leaks into the raw body either.
    [avoid_ingredient, avoid_tag, liked_ingredient.id, liked_tag.id, "strict"].each do |secret|
      expect(response.body).not_to include(secret), "leaked dietary value #{secret}"
    end
  end

  it "excludes hidden reviews from the count + recent list" do
    visible = create(:review, user: user, item: item, rating: 5, body: "Loved it.")
    hidden  = create(:review, user: user, item: create(:item, :published, restaurant: restaurant), rating: 1, body: "spam at https://x/")
    hidden.hide!(reason: "spam")

    get "/api/v1/users/#{user.handle}"

    body = response.parsed_body
    expect(body["reviews_count"]).to eq(1)
    expect(body["restaurants_reviewed_count"]).to eq(1)
    expect(body["recent_reviews"].map { |r| r["id"] }).to eq([visible.id])
  end

  it "caps recent_reviews at 10 (newest first)" do
    12.times do |i|
      r = create(:item, :published, restaurant: restaurant, name: "Item #{i}")
      create(:review, user: user, item: r, rating: 5, created_at: i.days.ago)
    end

    get "/api/v1/users/#{user.handle}"

    body = response.parsed_body
    expect(body["recent_reviews"].length).to eq(10)
    expect(body["reviews_count"]).to eq(12)
  end

  it "404s on an unknown handle" do
    get "/api/v1/users/no-such-handle"
    expect(response).to have_http_status(:not_found)
  end

  # Recursively collect every Hash key in a parsed JSON payload so a
  # dietary field can't hide inside a nested object.
  def deep_keys(obj)
    case obj
    when Hash  then obj.keys + obj.values.flat_map { |v| deep_keys(v) }
    when Array then obj.flat_map { |v| deep_keys(v) }
    else []
    end
  end
end
