# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::DeviceLocation do
  it "keeps a valid location, coarsened to about 110 m" do
    expect(described_class.from({ "lat" => 37.27531, "lng" => "-107.88012", "accuracy_m" => 12.4 }))
      .to eq("lat" => 37.275, "lng" => -107.88, "accuracy_m" => 12)
  end

  # Client-supplied: a bad location costs the sort, never the message.
  it "drops anything malformed rather than raising" do
    [ nil, "37,-107", [ 1, 2 ], { "lat" => 37 }, { "lat" => 91, "lng" => 0 },
      { "lat" => "x", "lng" => 1 }, { "lat" => true, "lng" => 1 }, { "lat" => "NaN", "lng" => 1 } ].each do |raw|
      expect(described_class.from(raw)).to be_nil, "expected #{raw.inspect} to be dropped"
    end
  end

  it "drops a nonsense accuracy but keeps the point" do
    expect(described_class.from({ "lat" => 1, "lng" => 2, "accuracy_m" => -5 })).to eq("lat" => 1.0, "lng" => 2.0)
  end
end
