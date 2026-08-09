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

    # The account page renders names, not UUIDs, so GET resolves each id
    # array to ordered {id, slug, name} rows in one payload. The raw id
    # arrays stay for the mobile/onboarding clients that read them.
    describe "resolved name rows" do
      let(:cheese)    { create(:ingredient, slug: "dairy-cheese") }
      let(:wheat)     { create(:ingredient, slug: "wheat") }
      let(:fried_tag) { create(:tag, slug: "prep-fried") }

      it "resolves avoid ids to {id, slug, name} rows in stored order" do
        user.profile.update!(
          avoid_ingredient_ids: [wheat.id, cheese.id],
          avoid_tag_ids:        [fried_tag.id]
        )

        get "/api/v1/profile", headers: headers

        body = response.parsed_body
        expect(body["avoid_ingredients"]).to eq([
          { "id" => wheat.id,  "slug" => "wheat",       "name" => "Wheat" },
          { "id" => cheese.id, "slug" => "dairy-cheese", "name" => "Cheese" }
        ])
        expect(body["avoid_tags"]).to eq([
          { "id" => fried_tag.id, "slug" => "prep-fried", "name" => "Fried", "family" => "prep" }
        ])
      end

      it "drops ids that no longer resolve to a live row (stale ids)" do
        stale = SecureRandom.uuid
        user.profile.update!(avoid_ingredient_ids: [cheese.id, stale])

        get "/api/v1/profile", headers: headers

        body = response.parsed_body
        expect(body["avoid_ingredient_ids"]).to contain_exactly(cheese.id, stale)
        expect(body["avoid_ingredients"].map { |r| r["id"] }).to eq([cheese.id])
      end
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

    # Wholesale replacement is right for a wizard and wrong for a settings
    # page. The wizard just built the list in front of the person, so what
    # it sends is the answer. A settings page sends an array rebuilt from
    # whatever it loaded at mount — and between that load and the click,
    # the chat or an MCP client may have added an allergen.
    describe "incremental edits" do
      it "adds without disturbing what is already there" do
        user.profile.update!(avoid_ingredient_ids: [cheese.id])

        patch "/api/v1/profile",
              params: { add_avoid_ingredient_ids: [wheat.id] }.to_json, headers: headers

        expect(user.profile.reload.avoid_ingredient_ids).to contain_exactly(cheese.id, wheat.id)
      end

      it "removes only what it names" do
        user.profile.update!(avoid_ingredient_ids: [cheese.id, wheat.id])

        patch "/api/v1/profile",
              params: { remove_avoid_ingredient_ids: [cheese.id] }.to_json, headers: headers

        expect(user.profile.reload.avoid_ingredient_ids).to eq([wheat.id])
      end

      it "works the same way for tags" do
        user.profile.update!(avoid_tag_ids: [vegan_tag.id])

        patch "/api/v1/profile",
              params: { add_avoid_tag_ids: [fried_tag.id] }.to_json, headers: headers

        expect(user.profile.reload.avoid_tag_ids).to contain_exactly(vegan_tag.id, fried_tag.id)
      end

      # The bug this exists to close, written as the story that produces
      # it: a settings page open since before the chat added an allergen.
      # Under replacement the stale array silently drops it, and somebody
      # is shown a dish that can hurt them.
      it "does not revert an avoid added by another client since the page loaded" do
        user.profile.update!(avoid_ingredient_ids: [cheese.id])
        stale_snapshot = [cheese.id]

        # Meanwhile, in the chat.
        user.profile.update!(avoid_ingredient_ids: stale_snapshot + [wheat.id])

        # The settings page removes cheese, knowing only what it loaded.
        patch "/api/v1/profile",
              params: { remove_avoid_ingredient_ids: [cheese.id] }.to_json, headers: headers

        expect(user.profile.reload.avoid_ingredient_ids).to eq([wheat.id])
      end

      it "is idempotent — re-adding does not duplicate" do
        patch "/api/v1/profile",
              params: { add_avoid_ingredient_ids: [cheese.id] }.to_json, headers: headers
        patch "/api/v1/profile",
              params: { add_avoid_ingredient_ids: [cheese.id] }.to_json, headers: headers

        expect(user.profile.reload.avoid_ingredient_ids).to eq([cheese.id])
      end

      # A client sending both forms does not know what it means, and
      # guessing which one wins is how an allergen goes missing quietly.
      it "refuses a list sent both wholesale and as a diff" do
        user.profile.update!(avoid_ingredient_ids: [cheese.id])

        patch "/api/v1/profile",
              params: { avoid_ingredient_ids: [wheat.id], remove_avoid_ingredient_ids: [cheese.id] }.to_json,
              headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.profile.reload.avoid_ingredient_ids).to eq([cheese.id])
      end

      # Onboarding still means what it says.
      it "leaves wholesale replacement alone when no diff is sent" do
        user.profile.update!(avoid_ingredient_ids: [cheese.id])

        patch "/api/v1/profile",
              params: { avoid_ingredient_ids: [wheat.id] }.to_json, headers: headers

        expect(user.profile.reload.avoid_ingredient_ids).to eq([wheat.id])
      end
    end

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

      # A taste id can go stale when an admin removes its taxonomy node.
      # A partial edit that doesn't touch taste must still succeed — it
      # must not re-validate (and reject on) the untouched stale array,
      # or the user is soft-locked out of editing every preference,
      # including their safety filter. update_columns seeds the stale id
      # past validation to mimic post-hoc taxonomy removal.
      it "does not re-validate an untouched taste array (stale id can't block an unrelated edit)" do
        user.profile.update_columns(liked_ingredient_ids: [SecureRandom.uuid])

        patch "/api/v1/profile",
              params: { strictness: "strict" }.to_json,
              headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["strictness"]).to eq("strict")
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
