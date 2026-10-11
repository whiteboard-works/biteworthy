require "rails_helper"

# Rows written before the standard existed keep their shouted text until
# something rewrites them; this is that something. It must preview
# before it writes, and must never touch a row that already conforms.
RSpec.describe Names::Backfill do
  let(:restaurant) { create(:restaurant) }
  let!(:shouted)   { create(:item, restaurant: restaurant) }
  let!(:clean)     { create(:item, restaurant: restaurant, name: "McDonald's Style Burger", description: "Two patties.") }

  # Pre-standard rows can only be made in raw SQL — `update_columns` and
  # `update_all` both normalize.
  def write_raw(item, **attrs)
    sets = attrs.map { |col, val| Item.sanitize_sql([ "#{col} = ?", val ]) }.join(", ")
    Item.connection.execute("UPDATE items SET #{sets} WHERE id = #{Item.connection.quote(item.id)}")
  end

  before { write_raw(shouted, name: "STEAK TARTARE*", description: "HAND-CUT BEEF. RAW EGG YOLK.") }

  it "previews the rewrite without writing on a dry run" do
    changes = described_class.new(restaurant.items).call(dry_run: true).changes

    expect(changes.map(&:item)).to eq([ shouted ])
    expect(changes.first.before).to eq(name: "STEAK TARTARE*", description: "HAND-CUT BEEF. RAW EGG YOLK.")
    expect(changes.first.after).to eq(name: "Steak Tartare", description: "Hand-cut beef. Raw egg yolk.")
    expect(shouted.reload.name).to eq("STEAK TARTARE*")
  end

  it "rewrites only the rows that do not conform" do
    expect { described_class.new(restaurant.items).call(dry_run: false) }
      .not_to(change { clean.reload.updated_at })

    expect(shouted.reload).to have_attributes(name: "Steak Tartare", description: "Hand-cut beef. Raw egg yolk.")
  end

  it "finds nothing left on a second run" do
    described_class.new(restaurant.items).call(dry_run: false)

    expect(described_class.new(restaurant.items).call(dry_run: true).changes).to be_empty
  end

  it "is limited to the scope it is given" do
    other = create(:item)
    write_raw(other, name: "PAD THAI")

    described_class.new(restaurant.items).call(dry_run: false)

    expect(other.reload.name).to eq("PAD THAI")
  end

  # The read is a snapshot; an owner's edit landing after it must win.
  it "leaves a row edited after it was read, and counts it as stale" do
    backfill = described_class.new(restaurant.items)
    allow(Names::Standard).to receive(:item_name).and_wrap_original do |original, name|
      write_raw(shouted, name: "OWNER RENAMED THIS") if name == "STEAK TARTARE*"
      original.call(name)
    end

    result = backfill.call(dry_run: false)

    expect(result.stale).to eq(1)
    expect(result.changes).to be_empty
    expect(shouted.reload.name).to eq("OWNER RENAMED THIS")
  end
end
