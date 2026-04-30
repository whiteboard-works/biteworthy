require "rails_helper"

RSpec.describe RecordRestaurantVisitJob, type: :job do
  let(:user)       { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:today)      { Date.current.iso8601 }

  it "creates a visit row with the given counts" do
    expect {
      described_class.perform_now(user.id, restaurant.id, 5, 2, today)
    }.to change(RestaurantVisit, :count).by(1)

    visit = RestaurantVisit.last
    expect(visit.user_id).to eq(user.id)
    expect(visit.restaurant_id).to eq(restaurant.id)
    expect(visit.viewed_on).to eq(Date.current)
    expect(visit.items_visible_count).to eq(5)
    expect(visit.items_hidden_count).to eq(2)
  end

  it "upserts the same (user, restaurant, day) instead of duplicating" do
    described_class.perform_now(user.id, restaurant.id, 5, 2, today)
    expect {
      described_class.perform_now(user.id, restaurant.id, 7, 1, today)
    }.not_to change(RestaurantVisit, :count)

    visit = RestaurantVisit.last
    expect(visit.items_visible_count).to eq(7) # latest counts win
    expect(visit.items_hidden_count).to eq(1)
  end

  it "creates separate rows for the same restaurant on different days" do
    yesterday = (Date.current - 1).iso8601
    described_class.perform_now(user.id, restaurant.id, 1, 0, yesterday)
    expect {
      described_class.perform_now(user.id, restaurant.id, 2, 0, today)
    }.to change(RestaurantVisit, :count).by(1)
  end

  it "swallows InvalidForeignKey when the restaurant was deleted between request + perform" do
    bogus_id = SecureRandom.uuid
    expect {
      described_class.perform_now(user.id, bogus_id, 1, 0, today)
    }.not_to raise_error
    expect(RestaurantVisit.count).to eq(0)
  end

  it "defaults viewed_on to today when no iso string is supplied" do
    described_class.perform_now(user.id, restaurant.id, 3, 1)
    expect(RestaurantVisit.last.viewed_on).to eq(Date.current)
  end
end
