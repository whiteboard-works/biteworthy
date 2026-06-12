require "rails_helper"

RSpec.describe Avo::Actions::Restaurants::ConfirmCommunity do
  let(:scanner) { create(:user, password: "password123", is_admin: false) }

  it "confirms across multiple selected restaurants and reports totals" do
    r1 = create(:restaurant, :published, created_by_user: scanner)
    r2 = create(:restaurant, :published, created_by_user: scanner)
    create(:item, :published, restaurant: r1, ingredients: [create(:ingredient, slug: "dairy-cheese")])
    create(:item, :published, restaurant: r2, tag_list: [create(:tag, slug: "cuisine-thai")])

    totals = described_class.confirm_all(Restaurant.where(id: [r1.id, r2.id]))

    expect(totals).to eq(restaurants: 2, items: 2, ingredients: 1, tags: 1)
    expect(Item.where(restaurant: [r1, r2]).pluck(:confidence)).to all(eq("confirmed"))
  end
end
