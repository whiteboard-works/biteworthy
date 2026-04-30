FactoryBot.define do
  factory :item_suggestion_pending, class: "Suggestion" do
    user
    subject { create(:item, :published) }
    kind    { "rename" }
    status  { "pending" }
    payload { { "name" => "Renamed item" } }
  end
end
