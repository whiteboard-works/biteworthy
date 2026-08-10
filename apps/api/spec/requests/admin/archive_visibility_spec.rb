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

    it "drops it from GET /profile/favorites" do
      get "/api/v1/profile/favorites", headers: bearer_for(member)
      expect(json_ids(response)).to include(restaurant.id)

      archive!
      get "/api/v1/profile/favorites", headers: bearer_for(member)
      expect(json_ids(response)).not_to include(restaurant.id)
    end

    it "drops it from the list_saved chat tool" do
      saved = -> { Tools::History::ListSaved.call(server_context: { user_id: member.id },
                                                  kind: "restaurants") }

      expect(saved_ids(saved.call)).to include(restaurant.id)

      archive!
      expect(saved_ids(saved.call)).not_to include(restaurant.id)
    end

    def saved_ids(response)
      response.to_h[:structuredContent].fetch(:restaurants).map { |r| r[:id] }
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
