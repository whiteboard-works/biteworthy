require "rails_helper"

# The standard is applied on assignment, so every writer — ingestion,
# the admin editor, the MCP tools, an owner edit — stores the same text
# without each one having to remember.
RSpec.describe "Item naming standard", type: :model do
  it "normalizes an item's name and description on save" do
    item = create(:item, name: "STEAK TARTARE*", description: "HAND-CUT BEEF. RAW EGG YOLK.")

    expect(item.reload.name).to eq("Steak Tartare")
    expect(item.description).to eq("Hand-cut beef. Raw egg yolk.")
  end

  it "normalizes a staged ingestion item, so a re-scan of an all-caps menu is not a change" do
    staged = create(:ingestion_item, name: "PAD THAI", description: "RICE NOODLES, TAMARIND.")

    expect(staged.name).to eq("Pad Thai")
    expect(staged.description).to eq("Rice noodles, tamarind.")
  end

  it "finds a record by the shouted form" do
    item = create(:item, name: "Pad Thai")

    expect(Item.find_by(name: "PAD THAI")).to eq(item)
  end
end
