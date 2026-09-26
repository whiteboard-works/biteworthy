require "rails_helper"

# The menu is the screen people wait on at the table, and the filter
# only stays cheap because it reads denormalized arrays instead of joining
# per dish. This fences the shape: a 30-dish menu must cost the same number
# of statements as a 3-dish one, anonymous or signed in with a full
# profile, so a per-item lookup fails here instead of on a long menu in
# production.
RSpec.describe "GET /api/v1/restaurants/:id/items query budget", type: :request do
  let(:restaurant) { create(:restaurant, :published) }
  let(:section)    { create(:menu_section, menu: create(:menu, restaurant: restaurant)) }
  let!(:cheddar)   { create(:ingredient, name: "Cheddar", slug: "dairy-cheddar", path: "dairy.cheddar") }
  let!(:spicy)     { create(:tag, name: "Spicy", slug: "flavor-spicy", family: "flavor") }

  let(:user) do
    create(:user).tap do |u|
      u.profile.update!(avoid_ingredient_ids: [ cheddar.id ], liked_tag_ids: [ spicy.id ], strictness: "strict")
    end
  end

  def add_dishes(count)
    create_list(:item, count, :published, restaurant: restaurant, menu_section: section,
                                          ingredients: [ cheddar ], tag_list: [ spicy ])
  end

  def count_queries
    queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached]
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  def menu_queries(headers = {})
    count_queries { get "/api/v1/restaurants/#{restaurant.slug}/items", headers: headers }
  end

  it "costs the same for a long menu as a short one, anonymously" do
    add_dishes(3)
    short = menu_queries
    add_dishes(27)

    expect(menu_queries).to eq(short)
    expect(response.parsed_body["items"].size).to eq(30)
  end

  # restaurant, items, sections, photos, review counts. The parent `menus`
  # row used to be preloaded too and nothing read it.
  it "reads only what the anonymous menu renders" do
    add_dishes(3)

    expect(menu_queries).to be <= 5
  end

  it "costs the same for a long menu as a short one, signed in with avoids and taste" do
    headers = auth_headers_for(user)
    add_dishes(3)
    short = menu_queries(headers)
    add_dishes(27)

    expect(menu_queries(headers)).to eq(short)
  end

  # Phase 8.x — implicit taste signals (favorites + the caller's own
  # reviews) add exactly two bounded, capped queries (see
  # Menus::ImplicitTasteSignals) regardless of how many dishes the
  # requested menu has, or how many favorites/reviews the caller has
  # elsewhere. This is the property this whole spec exists to fence.
  it "costs the same for a long menu as a short one, signed in with only implicit taste signals" do
    implicit_user     = create(:user)
    other_restaurant  = create(:restaurant, :published)
    favorited         = create(:item, :published, restaurant: other_restaurant, ingredients: [ cheddar ])
    reviewed          = create(:item, :published, restaurant: other_restaurant, tag_list: [ spicy ])
    create(:favorite_item, user: implicit_user, item: favorited)
    create(:review, user: implicit_user, item: reviewed, rating: 5)

    headers = auth_headers_for(implicit_user)
    add_dishes(3)
    short = menu_queries(headers)
    add_dishes(27)

    expect(menu_queries(headers)).to eq(short)
  end

  # The favorites/review lookup queries are bounded by LIMIT, not by how
  # much activity the caller has — favoriting/reviewing MORE dishes
  # elsewhere must not add more queries to this menu's cost.
  it "costs the same number of implicit-signal queries for 2 favorites/reviews as for 20" do
    other_restaurant = create(:restaurant, :published)
    add_dishes(3)

    light_user = create(:user)
    create_list(:item, 2, :published, restaurant: other_restaurant, ingredients: [ cheddar ]).each do |item|
      create(:favorite_item, user: light_user, item: item)
      create(:review, user: light_user, item: item, rating: 5)
    end
    light = menu_queries(auth_headers_for(light_user))

    heavy_user = create(:user)
    create_list(:item, 20, :published, restaurant: other_restaurant, ingredients: [ cheddar ]).each do |item|
      create(:favorite_item, user: heavy_user, item: item)
      create(:review, user: heavy_user, item: item, rating: 5)
    end

    expect(menu_queries(auth_headers_for(heavy_user))).to eq(light)
  end
end
