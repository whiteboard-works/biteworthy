require "rails_helper"
require Rails.root.join("db/migrate/20261010230000_upsert_cuisine_leaf_tags")

# `db:prepare` seeds only a freshly created database, so a cuisine added
# to `db/seeds/tags.yml` reaches production through this migration or not
# at all. The two lists have to agree, or a fresh database and the live
# one would disagree about what a cuisine is.
RSpec.describe UpsertCuisineLeafTags do
  let(:seeded) { YAML.load_file(Rails.root.join("db/seeds/tags.yml")) }

  before { create(:tag, slug: "cuisine", name: "Cuisine", family: "cuisine", path: "cuisine") }

  it "upserts every leaf the seed file carries beyond the original seven, with the same attributes" do
    described_class.new.up

    described_class::TAGS.each do |attrs|
      row  = Tag.find_by!(slug: attrs[:slug])
      seed = seeded.find { |r| r["slug"] == attrs[:slug] }
      expect(seed).to be_present, "#{attrs[:slug]} is not in tags.yml"
      expect([ row.name, row.family, row.path.to_s ]).to eq([ seed["name"], seed["family"], seed["path"] ])
    end
    expect(Tag.where(family: "cuisine").where("path <@ 'cuisine' AND path != 'cuisine'").count).to eq(16)
  end

  it "is idempotent and fixes a renamed leaf without duplicating it" do
    create(:tag, slug: "bbq", name: "BBQ", family: "cuisine", path: "cuisine.bbq")

    2.times { described_class.new.up }

    expect(Tag.where(slug: "bbq").count).to eq(1)
    expect(Tag.find_by!(slug: "bbq").name).to eq("Barbecue")
  end

  it "refuses to move a slug that already lives elsewhere in the tree" do
    create(:tag, slug: "greek", name: "Greek", family: "flavor", path: "flavor.greek")

    expect { described_class.new.up }.to raise_error(/greek exists at flavor/)
    expect(Tag.find_by!(slug: "greek").path.to_s).to eq("flavor.greek")
  end

  # A fresh database runs migrations before it is seeded; the seed file
  # carries these rows, so the migration must not create orphans there.
  it "does nothing under an unseeded taxonomy rather than create orphans" do
    Tag.where(path: "cuisine").delete_all

    expect { described_class.new.up }.to output(/not seeded/).to_stdout
    expect(Tag.where(slug: "greek")).not_to exist
  end
end
