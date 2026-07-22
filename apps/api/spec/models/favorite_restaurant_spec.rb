require "rails_helper"

RSpec.describe FavoriteRestaurant, type: :model do
  it "is valid with a user and restaurant" do
    expect(build(:favorite_restaurant)).to be_valid
  end

  it "enforces one favorite per (user, restaurant)" do
    fav = create(:favorite_restaurant)
    dup = build(:favorite_restaurant, user: fav.user, restaurant: fav.restaurant)
    expect(dup).not_to be_valid
  end

  it "lets two users favorite the same restaurant" do
    restaurant = create(:restaurant, :published)
    create(:favorite_restaurant, user: create(:user), restaurant: restaurant)
    expect(build(:favorite_restaurant, user: create(:user), restaurant: restaurant)).to be_valid
  end

  it "is reachable via user.favorited_restaurants and destroyed with the user" do
    fav = create(:favorite_restaurant)
    expect(fav.user.favorited_restaurants).to include(fav.restaurant)
    expect { fav.user.destroy }.to change(FavoriteRestaurant, :count).by(-1)
  end
end
