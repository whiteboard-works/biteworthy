require "rails_helper"

RSpec.describe UserItemOverride, type: :model do
  let(:user)       { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:item)       { create(:item, :published, restaurant: restaurant) }

  it "persists with sensible defaults" do
    override = described_class.create!(user: user, item: item)
    expect(override.never_hide).to be(true)
  end

  it "enforces uniqueness on (user_id, item_id)" do
    described_class.create!(user: user, item: item)
    duplicate = described_class.new(user: user, item: item)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to be_present
  end

  it "does not collide across users for the same item" do
    described_class.create!(user: user, item: item)
    other_user = create(:user)
    expect {
      described_class.create!(user: other_user, item: item)
    }.not_to raise_error
  end

  it "exposes the through-association on User" do
    described_class.create!(user: user, item: item)
    expect(user.overridden_items).to include(item)
  end

  it "tears down with the user" do
    described_class.create!(user: user, item: item)
    expect { user.destroy }.to change(described_class, :count).by(-1)
  end
end
