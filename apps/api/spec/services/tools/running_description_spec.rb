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
end
