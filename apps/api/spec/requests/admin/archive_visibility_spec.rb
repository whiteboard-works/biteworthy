require "rails_helper"

# A soft delete that leaves the thing visible is not a delete. The
# endpoints in `deletes_spec.rb` prove the archive is *recorded*; this
# proves it is *honoured*, which is the half that can rot.
#
# The design bet is that `Restaurant.published` is the single chokepoint
# every public read already goes through, so folding the archive check
# in there covers all of them at once. These examples are what makes
# that bet checkable: each one names a different reader, and any future
# reader that queries around `published` will fail here rather than
# quietly serving an archived restaurant.
RSpec.describe "archive visibility", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    { "Authorization" => "Bearer #{token}" }
  end

  let(:city)       { create(:city) }
  let(:restaurant) { create(:restaurant, :published, city: city) }
  let!(:item)      { create(:item, restaurant: restaurant, status: "published") }

  def archive!
    restaurant.update!(archived_at: Time.current)
  end

  describe "public reads" do
    it "drops the restaurant from the list" do
      get "/api/v1/restaurants"
      expect(json_ids(response)).to include(restaurant.id)

      archive!
      get "/api/v1/restaurants"
      expect(json_ids(response)).not_to include(restaurant.id)
    end

    it "404s the detail page, by slug as well as by id" do
      archive!

      get "/api/v1/restaurants/#{restaurant.id}"
      expect(response).to have_http_status(:not_found)

      get "/api/v1/restaurants/#{restaurant.slug}"
      expect(response).to have_http_status(:not_found)
    end

    # The menu is the product. An archived restaurant whose items still
    # answered would be the worst version of this bug: a filter verdict
    # served for a restaurant that no longer exists.
    it "404s the menu" do
      archive!
      get "/api/v1/restaurants/#{restaurant.id}/items"
      expect(response).to have_http_status(:not_found)
    end

    # Cities::RestaurantRanking builds its own query rather than calling
    # the items endpoint, so it is the reader most likely to be missed.
    it "drops it from the city ranking" do
      profile = create(:dietary_profile)
      ranking = -> { get "/api/v1/cities/#{city.slug}/restaurants", params: { profile: profile.slug } }

      ranking.call
      expect(json_ids(response)).to include(restaurant.id)

      archive!
      ranking.call
      expect(json_ids(response)).not_to include(restaurant.id)
    end
  end

  # These two readers show draft and closed restaurants on purpose, so
  # they do not go through `published` and do not inherit the archive
  # filter from it. They each filter on `kept` instead — and if that
  # ever gets dropped, a member's saved list keeps a bookmark that 404s
  # with no explanation.
  describe "saved lists, which deliberately bypass `published`" do
    let(:member) { create(:user) }

    before { create(:favorite_restaurant, user: member, restaurant: restaurant) }

    before { create(:favorite_item, user: member, item: item) }

    # Both halves. The dishes half was missed the first time, and the
    # failure is worse there than for restaurants: a saved dish carries
    # its restaurant's `status`, which archiving does not touch, so the
    # page renders a confident live link to a 404.
    it "drops the restaurant and the dish from GET /profile/favorites" do
      get "/api/v1/profile/favorites", headers: bearer_for(member)
      expect(json_ids(response)).to include(restaurant.id, item.id)

      archive!
      get "/api/v1/profile/favorites", headers: bearer_for(member)
      expect(json_ids(response)).not_to include(restaurant.id)
      expect(json_ids(response)).not_to include(item.id)
    end

    it "drops both from the list_saved chat tool" do
      saved = -> { Tools::History::ListSaved.call(server_context: { user_id: member.id }) }

      expect(saved_ids(saved.call)).to include(restaurant.id, item.id)

      archive!
      expect(saved_ids(saved.call)).not_to include(restaurant.id)
      expect(saved_ids(saved.call)).not_to include(item.id)
    end

    # A visit is a "recently viewed" link, and a link to a 404 is a dead
    # end rather than history. Third reader that bypasses `published`.
    it "drops it from browsing history, REST and tool alike" do
      create(:restaurant_visit, user: member, restaurant: restaurant)
      archive!

      get "/api/v1/profile/history", headers: bearer_for(member)
      expect(json_ids(response)).not_to include(restaurant.id)

      visits = Tools::History::ListVisits.call(server_context: { user_id: member.id })
      expect(visits.to_h[:structuredContent][:visits]).to be_empty
    end

    def saved_ids(response)
      c = response.to_h[:structuredContent]
      (c[:restaurants].to_a + c[:items].to_a).map { |r| r[:id] }
    end
  end

  # Scanning a *draft* restaurant is the normal case, so this cannot
  # use `published` — but a scan of an archived one buys nothing:
  # publishing the run flips `status` back while `archived_at` keeps it
  # hidden, so the Anthropic spend produces no visible menu.
  describe "starting a scan" do
    it "refuses an archived restaurant, by slug" do
      member = create(:user)
      archive!

      result = Tools::Ingestion::StartMenuScan.call(
        server_context: { user_id: member.id },
        restaurant: restaurant.slug, source_text: "Tacos $5"
      ).to_h

      expect(result[:structuredContent][:error]).to eq("not_found")
      expect(IngestionRun.count).to eq(0)
    end
  end

  describe "the admin list" do
    let(:admin_headers) { bearer_for(create(:user, :admin)) }

    it "hides archived restaurants by default but can still find them" do
      archive!

      get "/api/v1/admin/restaurants", headers: admin_headers
      expect(json_ids(response)).not_to include(restaurant.id)

      get "/api/v1/admin/restaurants", params: { archived: "true" }, headers: admin_headers
      expect(json_ids(response)).to include(restaurant.id)
    end

    # `community_published` chains off `published`, which now carries
    # `kept` — so combining it with the archived filter asked for
    # `archived_at IS NOT NULL AND archived_at IS NULL`, a lens that
    # could never return a row.
    it "can still find an archived community restaurant in the moderation lens" do
      restaurant.update!(created_by_user_id: create(:user).id)
      archive!

      get "/api/v1/admin/restaurants",
          params: { archived: "true", filter: "community_published" },
          headers: admin_headers

      expect(json_ids(response)).to include(restaurant.id)
    end
  end

  describe "ingestion runs" do
    let(:admin_headers) { bearer_for(create(:user, :admin)) }
    let!(:run) { create(:ingestion_run, status: "staged", api_cost_cents: 42) }

    it "drops an archived run from the queue and from the staged count" do
      get "/api/v1/admin/dashboard", headers: admin_headers
      expect(json_body(response).dig("queues", "staged_runs")).to eq(1)

      run.update!(archived_at: Time.current)

      get "/api/v1/admin/ingestion_runs", headers: admin_headers
      expect(json_ids(response)).not_to include(run.id)

      get "/api/v1/admin/dashboard", headers: admin_headers
      expect(json_body(response).dig("queues", "staged_runs")).to eq(0)
    end

    # Archiving a failed scan does not refund what it cost. If cost
    # reporting ever starts filtering on `kept`, spend silently
    # under-reports and the daily ceiling stops meaning anything.
    it "keeps counting an archived run's spend" do
      run.update!(archived_at: Time.current)

      bucket = Ingestion::CostMetrics.bucket_for(Time.current.all_day, label: "today")

      expect(bucket.to_h[:total_cost_cents]).to eq(42)
    end
  end

  def json_body(response) = JSON.parse(response.body)

  # Every list endpoint here nests its rows under a different key, and
  # the saved-favourites payload has two arrays. Pulling every `id` out
  # of the whole tree keeps the examples about visibility rather than
  # about payload shape.
  def json_ids(response)
    ids = []
    walk = lambda do |node|
      case node
      when Hash  then node.each { |k, v| k == "id" && v.is_a?(String) ? ids << v : walk.call(v) }
      when Array then node.each { |v| walk.call(v) }
      end
    end
    walk.call(json_body(response))
    ids
  end
end
