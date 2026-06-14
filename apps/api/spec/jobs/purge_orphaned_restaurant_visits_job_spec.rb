require "rails_helper"

RSpec.describe PurgeOrphanedRestaurantVisitsJob, type: :job do
  let(:user)       { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }

  it "leaves visits whose owner still exists untouched" do
    create(:restaurant_visit, user: user, restaurant: restaurant)

    expect {
      described_class.perform_now
    }.not_to change(RestaurantVisit, :count)
  end

  it "purges a visit row whose owning user is gone" do
    live_visit = create(:restaurant_visit, user: user, restaurant: restaurant)

    # The users FK normally makes orphans impossible. The backstop exists
    # for the case where referential integrity was bypassed (bulk SQL, a
    # restore, a future schema change), so the test simulates exactly
    # that: insert a visit pointing at a since-deleted user.
    ghost_id = SecureRandom.uuid
    orphan_id = SecureRandom.uuid
    ActiveRecord::Base.connection.disable_referential_integrity do
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        INSERT INTO restaurant_visits
          (id, user_id, restaurant_id, viewed_on, items_visible_count, items_hidden_count, created_at, updated_at)
        VALUES
          ('#{orphan_id}', '#{ghost_id}', '#{restaurant.id}', CURRENT_DATE, 3, 1, NOW(), NOW())
      SQL
    end

    expect(RestaurantVisit.exists?(orphan_id)).to be(true)

    purged = described_class.perform_now

    expect(purged).to eq(1)
    expect(RestaurantVisit.exists?(orphan_id)).to be(false)
    expect(RestaurantVisit.exists?(live_visit.id)).to be(true)
  end
end
