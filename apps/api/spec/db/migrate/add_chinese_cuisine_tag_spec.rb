# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261006000000_add_chinese_cuisine_tag")

RSpec.describe AddChineseCuisineTag, type: :migration do
  let(:migration) { described_class.new }

  it "creates chinese cuisine tag" do
    Tag.where(slug: "chinese").delete_all

    migration.up

    chinese = Tag.find_by(slug: "chinese")
    expect(chinese).to be_present
    expect(chinese.name).to eq("Chinese")
    expect(chinese.family).to eq("cuisine")
    expect(chinese.path.to_s).to eq("cuisine.chinese")
  end

  it "is idempotent" do
    Tag.where(slug: "chinese").delete_all

    migration.up
    migration.up

    expect(Tag.where(slug: "chinese").count).to eq(1)
  end

  it "raises IrreversibleMigration on down" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
