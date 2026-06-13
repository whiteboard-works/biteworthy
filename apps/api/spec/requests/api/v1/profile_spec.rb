require "rails_helper"

RSpec.describe "GET/PATCH /api/v1/profile", type: :request do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user).merge("Content-Type" => "application/json") }

  describe "GET /api/v1/profile" do
    it "returns the caller's profile with defaults" do
      get "/api/v1/profile", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include(
        "avoid_ingredient_ids" => [],
        "avoid_tag_ids"        => [],
        "prefer_tag_ids"       => [],
        "strictness"           => "balanced",
        "primary_dietary_profile" => nil
      )
    end

    it "rejects an unauthenticated caller with 401" do
      get "/api/v1/profile"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/profile" do
    # Real ingredients/tags from the curated factory lists so the
    # specs read like menu data — "dairy.cheese" and "diet.vegan"
    # instead of "ingredient-1" / "tag-2".
    let(:cheese)    { create(:ingredient, slug: "dairy-cheese") }
    let(:wheat)     { create(:ingredient, slug: "wheat") }
    let(:vegan_tag) { create(:tag, slug: "diet-vegan") }
    let(:fried_tag) { create(:tag, slug: "prep-fried") }

    it "round-trips avoid_ingredient_ids" do
      patch "/api/v1/profile",
            params: { avoid_ingredient_ids: [cheese.id, wheat.id] }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["avoid_ingredient_ids"])
        .to contain_exactly(cheese.id, wheat.id)

      expect(user.reload.profile.avoid_ingredient_ids)
        .to contain_exactly(cheese.id, wheat.id)
    end

    it "round-trips avoid_tag_ids and prefer_tag_ids" do
      patch "/api/v1/profile",
            params: { avoid_tag_ids: [fried_tag.id], prefer_tag_ids: [vegan_tag.id] }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["avoid_tag_ids"]).to  contain_exactly(fried_tag.id)
      expect(body["prefer_tag_ids"]).to contain_exactly(vegan_tag.id)
    end

    it "round-trips strictness" do
      patch "/api/v1/profile",
            params: { strictness: "strict" }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["strictness"]).to eq("strict")
    end

    it "rejects an unknown strictness value with 422" do
      patch "/api/v1/profile",
            params: { strictness: "yolo" }.to_json,
            headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to have_key("strictness")
    end

    it "replaces arrays wholesale (does not append)" do
      user.profile.update!(avoid_ingredient_ids: [cheese.id])

      patch "/api/v1/profile",
            params: { avoid_ingredient_ids: [wheat.id] }.to_json,
            headers: headers

      expect(response.parsed_body["avoid_ingredient_ids"])
        .to contain_exactly(wheat.id)
    end

    context "with a dietary_profile_slug" do
      let!(:vegan_preset) do
        preset = create(:dietary_profile, slug: "vegan")
        create(:dietary_profile_ingredient,
               dietary_profile: preset, ingredient: cheese, rule: "avoid")
        create(:dietary_profile_tag,
               dietary_profile: preset, tag: fried_tag, rule: "avoid")
        preset
      end

      it "additively unions the preset's avoid lists onto the user's" do
        # User started with wheat in avoid; preset adds cheese + fried.
        patch "/api/v1/profile",
              params: {
                avoid_ingredient_ids: [wheat.id],
                dietary_profile_slug: "vegan"
              }.to_json,
              headers: headers

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["avoid_ingredient_ids"]).to contain_exactly(wheat.id, cheese.id)
        expect(body["avoid_tag_ids"]).to        contain_exactly(fried_tag.id)
        expect(body["primary_dietary_profile"]).to include(
          "slug" => "vegan",
          "name" => "Vegan"
        )
      end

      it "is idempotent — re-applying does not duplicate ids" do
        2.times do
          patch "/api/v1/profile",
                params: { dietary_profile_slug: "vegan" }.to_json,
                headers: headers
        end

        body = response.parsed_body
        expect(body["avoid_ingredient_ids"]).to contain_exactly(cheese.id)
        expect(body["avoid_tag_ids"]).to        contain_exactly(fried_tag.id)
      end
    end

    it "404s on an unknown dietary_profile_slug" do
      patch "/api/v1/profile",
            params: { dietary_profile_slug: "no-such-preset" }.to_json,
            headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "rejects an unauthenticated caller with 401" do
      patch "/api/v1/profile",
            params: { strictness: "strict" }.to_json,
            headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end

    # Phase 8.1 — taste signals. Soft preferences that rank Top Picks;
    # they never hide items (that's the avoid arrays' job). The
    # validations exist because "loved AND hated" silently cancels in
    # scoring, and a deleted/typo'd UUID would be an invisible no-op
    # in the user's picks forever.
    describe "taste signals (Phase 8.1)" do
      let(:basil)     { create(:ingredient, slug: "herb-basil") }
      let(:spicy_tag) { create(:tag, slug: "flavor-spicy") }

      it "GET includes the four taste arrays (empty by default)" do
        get "/api/v1/profile", headers: headers

        expect(response.parsed_body).to include(
          "liked_ingredient_ids"    => [],
          "liked_tag_ids"           => [],
          "disliked_ingredient_ids" => [],
          "disliked_tag_ids"        => []
        )
      end

      it "round-trips all four taste arrays" do
        patch "/api/v1/profile",
              params: {
                liked_ingredient_ids:    [basil.id],
                liked_tag_ids:           [spicy_tag.id],
                disliked_ingredient_ids: [cheese.id],
                disliked_tag_ids:        [fried_tag.id]
              }.to_json,
              headers: headers

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["liked_ingredient_ids"]).to    contain_exactly(basil.id)
        expect(body["liked_tag_ids"]).to           contain_exactly(spicy_tag.id)
        expect(body["disliked_ingredient_ids"]).to contain_exactly(cheese.id)
        expect(body["disliked_tag_ids"]).to        contain_exactly(fried_tag.id)

        profile = user.reload.profile
        expect(profile.liked_ingredient_ids).to contain_exactly(basil.id)
        expect(profile.disliked_tag_ids).to     contain_exactly(fried_tag.id)
      end

      it "422s when an id appears in both liked and disliked" do
        patch "/api/v1/profile",
              params: {
                liked_ingredient_ids:    [basil.id],
                disliked_ingredient_ids: [basil.id]
              }.to_json,
              headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["errors"]).to have_key("liked_ingredient_ids")
      end

      it "422s on an unknown ingredient or tag UUID" do
        patch "/api/v1/profile",
              params: { liked_tag_ids: [SecureRandom.uuid] }.to_json,
              headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["errors"]).to have_key("liked_tag_ids")
      end

      it "accepts an id that also sits in an avoid list (filter wins; scoring ignores it)" do
        patch "/api/v1/profile",
              params: {
                avoid_ingredient_ids: [basil.id],
                liked_ingredient_ids: [basil.id]
              }.to_json,
              headers: headers

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["avoid_ingredient_ids"]).to contain_exactly(basil.id)
        expect(body["liked_ingredient_ids"]).to contain_exactly(basil.id)
      end
    end
  end
end
