# frozen_string_literal: true

require "rails_helper"

RSpec.describe AddChineseCuisineTag, type: :migration do
  let(:migration) { described_class.new }

  it "creates chinese cuisine tag" do
    # Run migration
    migration.up

    chinese = Tag.find_by(slug: "chinese")
    expect(chinese).to be_present
    expect(chinese.name).to eq("Chinese")
    expect(chinese.family).to eq("cuisine")
    expect(chinese.path).to eq("cuisine.chinese")
  end

  it "is idempotent" do
    # Run migration twice
    migration.up
    migration.up

    expect(Tag.where(slug: "chinese").count).to eq(1)
  end

  it "raises IrreversibleMigration on down" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
