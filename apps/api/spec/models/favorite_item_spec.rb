require "rails_helper"

RSpec.describe FavoriteItem, type: :model do
  it "is valid with a user and item" do
    expect(build(:favorite_item)).to be_valid
  end

  it "enforces one favorite per (user, item)" do
    fav = create(:favorite_item)
    dup = build(:favorite_item, user: fav.user, item: fav.item)
    expect(dup).not_to be_valid
  end

  it "lets two users favorite the same item" do
    item = create(:item, :published)
    create(:favorite_item, user: create(:user), item: item)
    expect(build(:favorite_item, user: create(:user), item: item)).to be_valid
  end

  it "is reachable via user.favorited_items and destroyed with the user" do
    fav = create(:favorite_item)
    expect(fav.user.favorited_items).to include(fav.item)
    expect { fav.user.destroy }.to change(FavoriteItem, :count).by(-1)
  end
end
