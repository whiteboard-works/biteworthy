require "rails_helper"

# The CHECK constraints added in 20260731160000 duplicate the model
# `validates :inclusion` lists as SQL literals — deliberately, since a
# migration has to keep meaning after the model moves on. The cost of
# that duplication is drift: add a value to a model constant without a
# follow-up migration and every write of the new value 500s in
# production while the test suite stays green.
#
# This spec is the guard. It reads the live constraint definition out
# of pg_constraint and asserts the value set matches the constant, so
# widening an enum fails here until a migration widens the constraint
# too.
RSpec.describe "enum CHECK constraints", type: :model do
  # column => the Ruby constant that must agree with the DB.
  PAIRS = {
    ["items", "status"]                        => Item::STATUSES,
    ["items", "confidence"]                    => Item::CONFIDENCE,
    ["item_ingredients", "confidence"]         => ItemIngredient::CONFIDENCE,
    ["item_ingredients", "source"]             => ItemIngredient::SOURCES,
    ["item_tags", "confidence"]                => ItemTag::CONFIDENCE,
    ["item_tags", "source"]                    => ItemTag::SOURCES,
    ["item_modifiers", "kind"]                 => ItemModifier::KINDS,
    ["restaurants", "status"]                  => Restaurant::STATUSES,
    ["user_profiles", "strictness"]            => UserProfile::STRICTNESS,
    ["ingestion_runs", "status"]               => IngestionRun::STATUSES,
    ["ingestion_runs", "input_kind"]           => IngestionRun::INPUT_KINDS,
    ["ingestion_runs", "enrichment_status"]    => IngestionRun::ENRICHMENT_STATUSES,
    ["ingestion_items", "decision"]            => IngestionItem::DECISIONS,
    ["tags", "family"]                         => Tag::FAMILIES,
    ["suggestions", "status"]                  => Suggestion::STATUSES,
    ["dmca_notices", "status"]                 => DmcaNotice::STATUSES,
    ["waitlist_signups", "source"]             => WaitlistSignup::SOURCES,
    ["reviews", "hidden_reason"]               => Review::HIDDEN_REASONS
  }.freeze

  # `pg_get_constraintdef` renders as e.g.
  #   CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, …])::text[])))
  # so pulling the single-quoted literals back out is exact — none of
  # these values contain a quote.
  def constraint_values(table, column)
    definition = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
      SELECT pg_get_constraintdef(oid)
      FROM pg_constraint
      WHERE conname = '#{table}_#{column}_valid'
    SQL
    raise "no CHECK constraint #{table}_#{column}_valid" if definition.nil?

    definition.scan(/'([^']*)'/).flatten.uniq
  end

  PAIRS.each do |(table, column), allowed|
    it "#{table}.#{column} accepts exactly #{allowed.inspect}" do
      expect(constraint_values(table, column)).to match_array(allowed)
    end
  end

  it "rejects a value outside the constant at the database level" do
    restaurant = create(:restaurant)
    item       = create(:item, restaurant: restaurant)

    # update_column skips every Rails validation — the exact hole
    # these constraints exist to close.
    expect { item.update_column(:status, "archived") }
      .to raise_error(ActiveRecord::StatementInvalid, /items_status_valid/)
  end

  it "still allows NULL where the column is nullable" do
    review = create(:review)
    expect { review.update_column(:hidden_reason, nil) }.not_to raise_error
  end
end
