# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorReports::Throttle do
  subject(:throttle) { described_class.new }

  it "lets the first occurrence in a window through and folds the rest into the next one" do
    expect(throttle.admit("a", now: 0)).to eq(1)
    expect(throttle.admit("a", now: 1)).to eq(0)
    expect(throttle.admit("a", now: 2)).to eq(0)
    expect(throttle.admit("a", now: described_class::WINDOW)).to eq(3)
    expect(throttle.admit("a", now: described_class::WINDOW + 1)).to eq(0)
  end

  it "keeps fingerprints apart" do
    expect(throttle.admit("a", now: 0)).to eq(1)
    expect(throttle.admit("b", now: 0)).to eq(1)
  end

  it "stays bounded under a flood of distinct fingerprints" do
    (described_class::MAX_KEYS * 2).times { |i| throttle.admit("f#{i}", now: i) }

    expect(throttle.instance_variable_get(:@seen).size).to be <= described_class::MAX_KEYS
  end
end
