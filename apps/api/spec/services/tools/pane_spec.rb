# frozen_string_literal: true

require "rails_helper"

# What each tool tells the results pane to show. The pane fetches the
# detail itself, so these pin only the reference — and that the reference
# is a tool's own account of its result, never the model's.
RSpec.describe "Tools pane" do
  it "get_menu points at the restaurant with only the overrides the model asked for" do
    data = {
      restaurant: { id: "r1", slug: "ninis", name: "Ninis" },
      filter: { source: "preset", preset: "vegan", strictness: "strict" },
      visible_count: 4, hidden_count: 9, items: []
    }

    expect(Tools::Registry.find("get_menu").pane_for({ restaurant: "ninis", diet: "vegan" }, data)).to eq(
      kind: "menu", restaurant: "ninis", preset: "vegan", visible_count: 4, hidden_count: 9
    )
  end

  # The saved profile is the pane's to resolve at fetch time. Sending the
  # resolved strictness would pin a reopened chat to the filter the person
  # had *then* — a safety-relevant menu drawn from a stale snapshot.
  it "get_menu leaves the caller's own filter out so the pane reads the current one" do
    data = { restaurant: { slug: "ninis" }, filter: { source: "user_profile", preset: nil, strictness: "strict" } }

    expect(Tools::Registry.find("get_menu").pane_for({ restaurant: "ninis" }, data)).to eq(kind: "menu", restaurant: "ninis")
  end

  it "every ingestion tool points at its scan" do
    scan = Tools::Registry.all.select { |t| t < Tools::Ingestion::Base }
    expect(scan.map(&:name_value)).to include("start_menu_scan", "accept_staged_items", "edit_staged_item")

    scan.each do |tool|
      expect(tool.pane_for({ scan_id: "run-1" }, {})).to eq(kind: "scan", scan_id: "run-1"), tool.name_value
    end
  end

  it "prefers the scan id the result names, with its status and restaurant" do
    tool = Tools::Registry.find("start_menu_scan")
    data = { scan_id: "run-2", status: "queued", restaurant: { slug: "ninis" } }

    expect(tool.pane_for({ restaurant: "ninis" }, data))
      .to eq(kind: "scan", scan_id: "run-2", status: "queued", restaurant: "ninis")
  end

  it "shows nothing when no scan can be named" do
    expect(Tools::Registry.find("edit_staged_item").pane_for({ item_id: "i-1" }, {})).to be_nil
  end

  it "only the tools that declared one have a pane" do
    with_pane = Tools::Registry.all.select(&:pane).map(&:name_value)
    expect(with_pane).to include("get_menu", "get_scan_status", "list_staged_items")
    expect(with_pane).not_to include("get_restaurant", "search_restaurants", "update_avoid_lists")
  end
end
