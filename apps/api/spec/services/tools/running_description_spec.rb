# frozen_string_literal: true

require "rails_helper"

# A tool with no running_description makes the chat show people a raw
# function name ("Did search_restaurants"), so every registered tool has to
# say what it is doing in words.
RSpec.describe "Tools running_description" do
  Tools::Registry.all.each do |tool|
    it "#{tool.name_value} describes itself in plain words" do
      expect(tool.running_description_for({})).to be_present.and be_a(String)
    end

    it "#{tool.name_value} tolerates odd arguments" do
      odd = { query: { a: 1 }, name: [ "x" ], restaurant: nil, slug: 5 }
      expect(tool.running_description_for(odd)).to be_a(String)
    end
  end

  # The sentence is the audit label a finished card keeps, so it has to
  # name what the call actually did, not the tool's headline action.
  it "says removing when save_item or save_restaurant unsaves" do
    expect(Tools::Registry.find("save_item").running_description_for(saved: false)).to start_with("Removing")
    expect(Tools::Registry.find("save_restaurant").running_description_for(saved: false)).to start_with("Removing")
  end

  it "names only the place fields edit_place was sent" do
    tool = Tools::Registry.find("edit_place")

    expect(tool.running_description_for(restaurant: "x", hours: [])).to eq("Updating the restaurant’s hours")
    expect(tool.running_description_for(restaurant: "x", street: "1 Main")).to eq("Updating the restaurant’s address")
  end
end
