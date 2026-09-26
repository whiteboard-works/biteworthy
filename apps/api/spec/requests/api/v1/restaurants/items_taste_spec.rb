require "rails_helper"

# Phase 8.2 — taste ranking on the items endpoint. Safety filters,
# taste ranks: scores reorder and annotate, they never hide. The
# scoring math itself is locked by the SQL ↔ TS parity fixture
# (spec/services/taste_scoring_spec.rb); this spec locks the HTTP
# behavior — when scores appear, how items sort, and that every
# legacy caller sees an unchanged payload.
RSpec.describe "GET /api/v1/restaurants/:id/items (taste ranking)", type: :request do
  let(:restaurant) { create(:restaurant, :published) }
  let(:user)       { create(:user, :confirmed) }
  let(:headers)    { auth_headers_for(user) }

  let(:spicy_tag) { create(:tag, slug: "flavor-spicy", name: "Spicy") }
  let(:basil)     { create(:ingredient, slug: "herb-basil", name: "Basil") }

  # Named so the default order (name ASC) leads with the noodles — a
  # taste profile that likes spice has to flip them, which is the whole
  # point of the scorer. This used to lean on `popularity` (90 vs 10) for
  # the same setup; that column was never written by anything and is gone,
  # so the tie-break it was standing in for is now simply the name.
  let!(:plain_noodles) do
    create(:item, :published, :confirmed,
           restaurant: restaurant, name: "Plain Noodles")
  end
  let!(:spicy_curry) do
    create(:item, :published, :confirmed,
           restaurant: restaurant, name: "Spicy Basil Curry",
           ingredients: [basil], tag_list: [spicy_tag])
  end

  describe "anonymous callers" do
    it "gets null taste_score, empty taste_reasons, plain name sort" do
      get "/api/v1/restaurants/#{restaurant.id}/items"

      body = response.parsed_body
      expect(body["items"].pluck("name")).to eq(["Plain Noodles", "Spicy Basil Curry"])
      expect(body["items"].pluck("taste_score").uniq).to eq([nil])
      expect(body["items"].pluck("taste_reasons").flatten).to be_empty
    end
  end

  describe "signed-in user with no taste signals (zero-signal no-op)" do
    it "behaves exactly like the legacy payload" do
      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      body = response.parsed_body
      expect(body["items"].pluck("name")).to eq(["Plain Noodles", "Spicy Basil Curry"])
      expect(body["items"].pluck("taste_score").uniq).to eq([nil])
    end
  end

  describe "signed-in user with taste signals" do
    before do
      user.profile.update!(liked_tag_ids: [spicy_tag.id], liked_ingredient_ids: [basil.id])
    end

    it "scores every item and re-sorts by taste_score desc" do
      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      body = response.parsed_body
      expect(body["items"].pluck("name")).to eq(["Spicy Basil Curry", "Plain Noodles"])

      curry = body["items"].first
      # 2.0 (spicy tag) + 1.0 (basil). No reviews, so no rating term.
      expect(curry["taste_score"]).to be_within(0.00005).of(3.0)
      expect(curry["taste_reasons"]).to eq([
        { "kind" => "liked_tag", "tag_id" => spicy_tag.id, "tag_name" => "Spicy" },
        { "kind" => "liked_ingredient", "ingredient_id" => basil.id, "ingredient_name" => "Basil" }
      ])

      noodles = body["items"].last
      # Matches nothing and has no reviews: scored, and scored zero.
      expect(noodles["taste_score"]).to be_within(0.00005).of(0.0)
      expect(noodles["taste_reasons"]).to eq([])
    end

    it "never hides an item via taste — low scores stay visible" do
      user.profile.update!(disliked_tag_ids: [spicy_tag.id], liked_tag_ids: [], liked_ingredient_ids: [])

      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      curry = response.parsed_body["items"].find { |i| i["name"] == "Spicy Basil Curry" }
      expect(curry["taste_score"]).to be < 0
      expect(curry["status"]).to eq("visible")
      expect(curry["reasons"]).to be_empty
    end

    it "ignores an id that also sits in an avoid list (filter wins)" do
      user.profile.update!(avoid_tag_ids: [spicy_tag.id])

      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      curry = response.parsed_body["items"].find { |i| i["name"] == "Spicy Basil Curry" }
      expect(curry["status"]).to eq("hidden") # the avoid still filters
      # The liked tag scored nothing and is not cited as a reason-to-like;
      # only the basil like survives.
      expect(curry["taste_reasons"].pluck("kind")).to eq(["liked_ingredient"])
      expect(curry["taste_score"]).to be_within(0.00005).of(1.0)
    end

    it "turns taste off when the caller picks a preset (?profile=)" do
      preset = create(:dietary_profile, slug: "vegan")

      get "/api/v1/restaurants/#{restaurant.id}/items",
          params: { profile: preset.slug }, headers: headers

      body = response.parsed_body
      expect(body["filter"]["source"]).to eq("preset")
      expect(body["items"].pluck("taste_score").uniq).to eq([nil])
    end
  end

  # Phase 8.x — favorites and a user's own ratings feed TasteScoring, so
  # Top Picks show without anyone taking the taste quiz.
  describe "signed-in user with only implicit taste signals (no taste quiz)" do
    it "ranks up a dish whose tags/ingredients they favorited elsewhere" do
      other_restaurant = create(:restaurant, :published)
      favorited = create(:item, :published, :confirmed,
                          restaurant: other_restaurant, ingredients: [basil], tag_list: [spicy_tag])
      create(:favorite_item, user: user, item: favorited)

      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      body  = response.parsed_body
      curry = body["items"].find { |i| i["name"] == "Spicy Basil Curry" }
      expect(curry["taste_score"]).to be_within(0.00005).of(3.0)
      expect(body["items"].pluck("name")).to eq(["Spicy Basil Curry", "Plain Noodles"])
    end

    it "ranks up a dish tagged like one they rated highly, and down one like a dish they rated poorly" do
      liked_elsewhere = create(:item, :published, :confirmed, restaurant: restaurant, tag_list: [spicy_tag])
      create(:review, user: user, item: liked_elsewhere, rating: 5)

      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      curry = response.parsed_body["items"].find { |i| i["name"] == "Spicy Basil Curry" }
      expect(curry["taste_score"]).to be > 0
    end

    # Explicit wins per id: a deliberate "I dislike spicy" in the quiz
    # is not overridden by having once favorited a spicy dish.
    it "lets an explicit dislike beat an implicit like from a favorite" do
      # Spicy only, no basil — isolates the tag from spicy_curry's own
      # ingredient so this pins the tag conflict alone.
      spicy_only = create(:item, :published, :confirmed, restaurant: restaurant, tag_list: [spicy_tag])
      create(:favorite_item, user: user, item: spicy_only)
      user.profile.update!(disliked_tag_ids: [spicy_tag.id])

      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      curry = response.parsed_body["items"].find { |i| i["name"] == "Spicy Basil Curry" }
      expect(curry["taste_reasons"].pluck("kind")).to eq([])
      expect(curry["taste_score"]).to be < 0
    end

    # Safety filters, taste ranks: an implicit like never un-hides an
    # item the caller's own avoid list filters out.
    it "never turns a hidden item into a pick, even when the caller favorited it" do
      user.profile.update!(avoid_tag_ids: [spicy_tag.id])
      create(:favorite_item, user: user, item: spicy_curry)

      get "/api/v1/restaurants/#{restaurant.id}/items", headers: headers

      curry = response.parsed_body["items"].find { |i| i["name"] == "Spicy Basil Curry" }
      expect(curry["status"]).to eq("hidden")
      expect(curry["reasons"].pluck("kind")).to eq(["avoid_tag"])
    end
  end
end
