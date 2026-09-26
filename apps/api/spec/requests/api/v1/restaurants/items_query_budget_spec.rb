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
end
