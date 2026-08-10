require "rails_helper"

# `destroy!` is only as complete as the model's `dependent:` list, and
# the database has the final say — every foreign key here is a plain
# `REFERENCES` with no `ON DELETE`, so anything the Ruby side forgets
# arrives as `ActiveRecord::InvalidForeignKey`, which is a 500 rather
# than a refusal.
#
# The admin hard delete is the first caller that destroys these rows
# with a full graph hanging off them, so this is where that list gets
# checked. Each example attaches every table that references the row
# and then deletes it; a new FK added without a matching `dependent:`
# fails here rather than in production on the one restaurant that had
# been scanned.
RSpec.describe "hard delete cascades" do
  describe "Restaurant" do
    let(:restaurant) { create(:restaurant) }

    it "destroys with its whole graph attached" do
      item = create(:item, restaurant: restaurant)
      Address.create!(restaurant: restaurant)
      Hour.create!(restaurant: restaurant, day_of_week: 1)
      create(:menu, restaurant: restaurant)
      create(:favorite_restaurant, user: create(:user), restaurant: restaurant)
      create(:restaurant_visit, user: create(:user), restaurant: restaurant)
      run = create(:ingestion_run, restaurant: restaurant)
      create(:ingestion_item, ingestion_run: run, item: item)

      expect { restaurant.destroy! }.not_to raise_error
      expect(Restaurant.exists?(restaurant.id)).to be(false)
    end

    # `suggestions.subject` is polymorphic: no foreign key to catch this
    # and no association to cascade it. The orphan is worse than a leak
    # — `belongs_to :subject` is required, so it can never be rejected
    # ("Subject must exist") while it keeps counting in the dashboard's
    # pending queue. A restaurant claim is a suggestion with a
    # Restaurant subject, which is how a claimed restaurant could
    # strand its own claim forever.
    it "takes the suggestions filed against it, claims included" do
      claim = Suggestion.create!(subject: restaurant, user: create(:user),
                                 kind: "claim", status: "pending", payload: {})

      restaurant.destroy!

      expect(Suggestion.exists?(claim.id)).to be(false)
    end

    # The scan is what the restaurant cost to build, and
    # Ingestion::CostMetrics reports on runs by date, not by
    # restaurant. Destroying the spend record along with the
    # restaurant would quietly reduce a historical total.
    it "keeps the ingestion run, and its recorded spend, as an orphan" do
      run = create(:ingestion_run, restaurant: restaurant, api_cost_cents: 40)

      restaurant.destroy!

      expect(run.reload.restaurant_id).to be_nil
      expect(run.api_cost_cents).to eq(40)
    end
  end

  describe "Item" do
    it "destroys with its whole graph attached" do
      item = create(:item)
      ItemVariant.create!(item: item)
      ItemModifier.create!(item: item, kind: "addition", name: "avocado")
      create(:review, item: item)
      create(:favorite_item, user: create(:user), item: item)
      create(:user_item_override, user: create(:user), item: item)
      ItemIngredient.create!(item: item, ingredient: create(:ingredient),
                             confidence: "confirmed", source: "human")
      ItemTag.create!(item: item, tag: create(:tag),
                      confidence: "confirmed", source: "human")
      create(:ingestion_item, item: item)

      expect { item.destroy! }.not_to raise_error
    end

    # Nullify was the first instinct and it was wrong: `decision:
    # "accepted"` with `item_id: nil` is exactly the shape two paths
    # read as "accepted but not yet promoted". ReExtractRun would stop
    # refusing to rewind a run whose items had shipped, and ResolveRun
    # would re-create the item an admin had just deleted.
    it "takes the staged row with it rather than orphaning a decision" do
      item = create(:item)
      staged = create(:ingestion_item, item: item, decision: "accepted")

      item.destroy!

      expect(IngestionItem.exists?(staged.id)).to be(false)
    end

    it "takes the suggestions filed against it" do
      item = create(:item)
      suggestion = create(:item_suggestion_pending, subject: item)

      item.destroy!

      expect(Suggestion.exists?(suggestion.id)).to be(false)
    end
  end

  describe "User" do
    it "destroys with its whole graph attached, including OAuth grants" do
      user = create(:user)
      item = create(:item, created_by_user: user)
      create(:review, user: user, item: item)
      create(:favorite_item, user: user, item: item)
      create(:favorite_restaurant, user: user, restaurant: item.restaurant)
      create(:user_item_override, user: user, item: item)
      create(:restaurant_visit, user: user, restaurant: item.restaurant)
      create(:ingestion_run, user: user)
      create(:conversation, user: user)

      app = Doorkeeper::Application.create!(
        name: "probe", redirect_uri: "https://example.test/cb", scopes: "profile:read"
      )
      Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: "profile:read")
      Doorkeeper::AccessGrant.create!(
        application: app, resource_owner_id: user.id, scopes: "profile:read",
        redirect_uri: "https://example.test/cb", expires_in: 600
      )

      expect { user.destroy! }.not_to raise_error
    end
  end
end
