require "rails_helper"

# The correction queue is where a stranger's opinion becomes live filter
# data. Two things have to hold: only the verified owner (or an admin)
# can accept, and an accepted removal really does change what gets hidden
# — so the tool must be honest that it is destructive.
RSpec.describe "suggestion tools" do
  let(:submitter)  { create(:user) }
  let(:owner)      { create(:user) }
  let(:stranger)   { create(:user) }
  let(:admin)      { create(:user, is_admin: true) }
  let(:restaurant) { create(:restaurant, :published, claimed_by_user_id: owner.id, claimed_at: Time.current) }
  let!(:dairy)     { create(:ingredient, name: "Cheddar", slug: "dairy-cheddar", path: "dairy.cheddar") }
  let(:item)       { create(:item, :published, restaurant: restaurant, ingredients: [dairy]) }

  def payload(response) = response.to_h[:structuredContent]
  def call(tool, user, **args) = tool.call(server_context: { user_id: user&.id }, **args)

  describe Tools::Suggestions::SuggestCorrection do
    it "queues a pending correction without touching the live dish" do
      response = call(described_class, submitter,
                      item_id: item.id, kind: "remove_ingredient", slug: "dairy-cheddar")

      expect(payload(response)[:status]).to eq("pending")
      expect(item.reload.denormalized_ingredient_ids).to include(dairy.id)
    end

    # A bad slug caught here is the submitter's problem; caught at accept
    # time it becomes the owner's, days later, with no way to fix it.
    it "rejects an unknown slug at submit time" do
      response = call(described_class, submitter,
                      item_id: item.id, kind: "add_ingredient", slug: "not-a-real-thing")

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(payload(response)[:message]).to include("search_taxonomy")
      expect(Suggestion.count).to eq(0)
    end

    it "needs a name for a rename" do
      response = call(described_class, submitter, item_id: item.id, kind: "rename")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end

    it "refuses a kind the resolver cannot apply" do
      response = call(described_class, submitter, item_id: item.id, kind: "delete_the_restaurant")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end
  end

  describe Tools::Suggestions::ListSuggestions do
    let!(:pending) do
      Suggestion.create!(user: submitter, subject: item, kind: "rename",
                         status: "pending", payload: { "name" => "Nachos" })
    end

    it "shows the owner their queue" do
      response = call(described_class, owner, restaurant: restaurant.slug)

      expect(payload(response)[:suggestions].map { |s| s[:id] }).to eq([pending.id])
    end

    it "shows an admin any queue" do
      response = call(described_class, admin, restaurant: restaurant.slug)

      expect(payload(response)[:suggestions].size).to eq(1)
    end

    # An unclaimed restaurant's queue is nobody's but an admin's.
    it "refuses a signed-in stranger" do
      response = call(described_class, stranger, restaurant: restaurant.slug)

      expect(payload(response)[:error]).to eq("forbidden")
    end

    it "refuses an anonymous caller" do
      response = call(described_class, nil, restaurant: restaurant.slug)

      expect(payload(response)[:error]).to eq("unauthorized")
    end
  end

  describe Tools::Suggestions::ResolveSuggestion do
    let!(:removal) do
      Suggestion.create!(user: submitter, subject: item, kind: "remove_ingredient",
                         status: "pending", payload: { "ingredient_slug" => "dairy-cheddar" })
    end

    # This is the safety-critical path: accepting a removal un-hides the
    # dish for everyone avoiding that ingredient.
    it "applies an accepted removal to the live dish" do
      response = call(described_class, owner, suggestion_id: removal.id, decision: "accepted")

      expect(payload(response)[:status]).to eq("accepted")
      expect(item.reload.denormalized_ingredient_ids).not_to include(dairy.id)
    end

    it "leaves the dish alone when rejected" do
      call(described_class, owner, suggestion_id: removal.id, decision: "rejected")

      expect(removal.reload.status).to eq("rejected")
      expect(item.reload.denormalized_ingredient_ids).to include(dairy.id)
    end

    it "refuses a stranger, and the dish keeps its ingredient" do
      response = call(described_class, stranger, suggestion_id: removal.id, decision: "accepted")

      expect(payload(response)[:error]).to eq("forbidden")
      expect(removal.reload.status).to eq("pending")
      expect(item.reload.denormalized_ingredient_ids).to include(dairy.id)
    end

    it "rejects a decision it does not understand" do
      response = call(described_class, owner, suggestion_id: removal.id, decision: "maybe")

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(removal.reload.status).to eq("pending")
    end

    # Accepting writes to a live menu; a client that reads annotations
    # must be able to confirm first.
    it "is annotated destructive" do
      expect(described_class.annotations_value.destructive_hint).to be(true)
    end
  end
end
