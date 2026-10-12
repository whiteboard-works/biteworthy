require "rails_helper"

RSpec.describe Tools::Discovery::SearchTaxonomy do
  def slugs(query, kind: "ingredient", limit: 3)
    response = described_class.call(query: query, kind: kind, limit: limit, server_context: {})
    response.to_h[:structuredContent][:ingredients].map { |r| r[:slug] }
  end

  # Ordered by path, "egg" returned Vegetable Broth, Parmesan, and Taleggio
  # (they contain "egg" in a name or alias) before Egg itself, and a
  # small limit cut Egg off entirely.
  it "ranks an exact name or alias first, then names that start with the query" do
    create(:ingredient, slug: "condiment-broths-vegetable-broth", name: "Vegetable Broth",
                        path: "condiment.broths.vegetable_broth", aliases: [ "veggie stock" ])
    create(:ingredient, slug: "dairy-taleggio", name: "Taleggio", path: "dairy.taleggio", aliases: [])
    create(:ingredient, slug: "vegetable-eggplant", name: "Eggplant", path: "vegetable.eggplant", aliases: [])
    create(:ingredient, slug: "egg", name: "Egg", path: "egg", aliases: [ "eggs" ])

    expect(slugs("egg", limit: 2)).to eq(%w[egg vegetable-eggplant])
    expect(slugs("eggs", limit: 1)).to eq(%w[egg])
  end
end
