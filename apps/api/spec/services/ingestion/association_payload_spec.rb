require "rails_helper"

RSpec.describe Ingestion::AssociationPayload do
  # Staged rows already in the database are string-keyed jsonb. Emitting
  # anything else would leave every previously-staged scan unreadable by the
  # verify tools, so the on-disk shape is a contract, not a detail.
  it "dumps string keys, always all three" do
    expect(described_class.dump(slug: "meat-beef", confidence: 0.9, source: "ai"))
      .to eq({ "slug" => "meat-beef", "confidence" => 0.9, "source" => "ai" })
  end

  it "loads a string-keyed row back out of jsonb" do
    row = described_class.load({ "slug" => "meat-beef", "confidence" => 0.9, "source" => "match" })

    expect(row.slug).to eq("meat-beef")
    expect(row.confidence).to eq(0.9)
    expect(row.source).to eq("match")
  end

  # The same shape arrives symbol-keyed from the matcher and from tool
  # arguments, before it has ever round-tripped through jsonb.
  it "loads a symbol-keyed row identically" do
    expect(described_class.load({ slug: "meat-beef", confidence: 0.9, source: "match" }))
      .to eq(described_class.load({ "slug" => "meat-beef", "confidence" => 0.9, "source" => "match" }))
  end

  it "ignores extra keys the matcher carries around" do
    expect(described_class.load({ slug: "meat-beef", path: "meat.beef", confidence: 0.9 }).slug)
      .to eq("meat-beef")
  end

  it "survives a row that is not a hash at all" do
    expect(described_class.load(nil).slug).to be_nil
  end
end
