require "rails_helper"

RSpec.describe Ingestion::JevCuisineTagger do
  let(:run) { create(:ingestion_run, :staged, enrichment_status: "pending") }
  let(:client) { TypesafeClient.new(api_key: "test-key", model: "jev-latest") }

  let(:rows) do
    [ { name: "Carbonara", description: "egg, pecorino, guanciale", section: "Pasta" },
     { name: "Carnitas Tacos", description: nil, section: "Tacos" } ]
  end

  let(:answers) do
    { "i0__any"     => { "type" => "noul", "noul" => 0.99 },
      "i1__any"     => { "type" => "noul", "noul" => 0.98 },
      "i0__italian" => { "type" => "noul", "noul" => 0.97 },
      "i0__mexican" => { "type" => "noul", "noul" => 0.02 },
      "i1__italian" => { "type" => "noul", "noul" => 0.03 },
      "i1__mexican" => { "type" => "noul", "noul" => 0.96 } }
  end

  before do
    create(:tag, slug: "cuisine", name: "Cuisine", family: "cuisine", path: "cuisine")
    create(:tag, slug: "italian", name: "Italian", family: "cuisine", path: "cuisine.italian")
    create(:tag, slug: "mexican", name: "Mexican", family: "cuisine", path: "cuisine.mexican")
    allow(Rails.logger).to receive(:info) { |msg| info_lines << msg }
    allow(Rails.logger).to receive(:warn)
  end

  def stub_jev(status: 200, body: { model: "jev-1.13.0", answers: answers, usage: { input_tokens: 400 } })
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .with(headers: { "Authorization" => "Bearer test-key" })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  let(:info_lines) { [] }

  def logged_line
    lines = info_lines.grep(/\A\[jev_cuisine\] /)
    expect(lines.size).to eq(1)
    JSON.parse(lines.first.delete_prefix("[jev_cuisine] "))
  end

  # The probability travels with the row: ConfidenceMapper grades an
  # `ai` row by it, so a 0.97 lands as "suggested" and a 0.6 as "inferred".
  it "keeps each tag whose probability reaches the threshold, with the probability as its confidence" do
    stub_jev
    rows_out = described_class.new(client: client).call(run, rows)

    expect(rows_out).to eq(
      0 => [ { "slug" => "italian", "confidence" => 0.97 } ],
      1 => [ { "slug" => "mexican", "confidence" => 0.96 } ]
    )
    expect(logged_line).to include("model" => "jev-1.13.0", "items" => 2, "tagged" => 2, "missing" => 0,
                                   "input_tokens" => 400)
  end

  # The log line dies with the container; the row is what a later
  # reading of the trial, or of a live failure, has to go on.
  it "records every call as an observation on the run: answered, partial, or failed" do
    stub_jev
    described_class.new(client: client).call(run, rows, context: { attempt: 1 })
    answers.delete("i1__mexican")
    stub_jev
    allow(Rails.error).to receive(:report)
    described_class.new(client: client).call(run, rows, context: { dry_run: true })
    stub_jev(status: 401, body: { error: "invalid key" })
    described_class.new(client: client).call(run, rows)

    kept = JevObservation.where(kind: "cuisine", subject: run).order(:created_at)
    expect(kept.map(&:outcome)).to eq(%w[answered partial failed])
    expect(kept.first).to have_attributes(model: "jev-1.13.0", input_tokens: 400)
    expect(kept.first.details).to include("items" => 2, "tagged" => 2, "no_cuisine" => 0, "missing" => 0,
                                          "attempt" => 1)
    expect(kept.second.details).to include("missing" => 1, "dry_run" => true)
    # A failed call may still have been billed, so it keeps its timing and
    # its status, and never a response body.
    expect(kept.third.details).to eq("items" => 2, "error" => "TypesafeClient::ApiError", "status" => 401)
    expect(kept.third.latency_ms).to be_a(Integer)
    # And never the previous call's model or tokens.
    expect(kept.third).to have_attributes(model: nil, input_tokens: nil)
  end

  it "writes one row, not two, when the partial-answer report itself raises" do
    answers.delete("i1__mexican")
    stub_jev
    # Rails' reporter never lets a subscriber raise out of `report`; the
    # stub stands in for the one call whose failure would matter here.
    allow(Rails.error).to receive(:report).and_call_original
    allow(Rails.error).to receive(:report).with(an_instance_of(described_class::PartialAnswers), anything)
                                           .and_raise("exporter down")
    allow(Rails.logger).to receive(:warn)

    expect { described_class.new(client: client).call(run, rows) }.not_to raise_error
    expect(JevObservation.where(kind: "cuisine", subject: run).pluck(:outcome)).to eq([ "failed" ])
  end

  it "asks one gate and one question per leaf cuisine, each with criteria, with state limited to the dishes themselves" do
    request = stub_jev
    described_class.new(client: client).call(run, rows)

    expect(request.with { |req|
      body = JSON.parse(req.body)
      body["questions"].keys.sort == %w[i0__any i0__italian i0__mexican i1__any i1__italian i1__mexican] &&
        body["questions"].values.all? { |q| q["type"] == "noul" && q["criteria"].keys.sort == %w[false true] } &&
        body["questions"]["i0__italian"]["criteria"]["true"]["not_for"].include?("sold at a Italian restaurant") &&
        body["questions"]["i0__any"]["criteria"]["true"]["examples"].include?("prosciutto-wrapped asparagus") &&
        body["questions"]["i0__italian"]["criteria"]["false"]["examples"] == [ "Italian soda", "Italian dressing" ] &&
        !body["questions"]["i0__mexican"]["criteria"]["false"].key?("examples") &&
        body["state"] == { "items" => [
          { "name" => "Carbonara", "description" => "egg, pecorino, guanciale", "section" => "Pasta" },
          { "name" => "Carnitas Tacos", "section" => "Tacos" }
        ] }
    }).to have_been_made
  end

  # The restaurant around a soda is not the soda's cuisine. A gate "no"
  # is a real answer: an empty row set, not a missing one.
  it "gives an item that belongs to no cuisine an empty row set without reading its cuisine answers" do
    answers["i1__any"]["noul"] = 0.05
    stub_jev
    rows_out = described_class.new(client: client).call(run, rows)

    expect(rows_out).to eq(0 => [ { "slug" => "italian", "confidence" => 0.97 } ], 1 => [])
    expect(logged_line).to include("tagged" => 1, "no_cuisine" => 1, "missing" => 0)
  end

  # The gate blocks only the obvious; a borderline item is decided by
  # the cuisine questions, so a wrong "probably not" cannot erase a tag.
  it "lets a borderline gate answer fall through to the cuisine questions" do
    answers["i1__any"]["noul"] = 0.4
    stub_jev
    rows_out = described_class.new(client: client).call(run, rows)

    expect(rows_out[1]).to eq([ { "slug" => "mexican", "confidence" => 0.96 } ])
    expect(logged_line).to include("no_cuisine" => 0)
  end

  it "treats a missing gate answer as a missing item, not as a no" do
    answers.delete("i1__any")
    stub_jev
    allow(Rails.error).to receive(:report)
    rows_out = described_class.new(client: client).call(run, rows)

    expect(rows_out).to eq(0 => [ { "slug" => "italian", "confidence" => 0.97 } ], 1 => nil)
    expect(logged_line).to include("missing" => 1)
  end

  it "turns an absent or out-of-range answer into no tag, counts it, and reports it instead of guessing" do
    answers.delete("i1__mexican")
    answers["i1__italian"] = { "type" => "noul", "noul" => 1.7 }
    stub_jev
    allow(Rails.error).to receive(:report)
    rows_out = described_class.new(client: client).call(run, rows)

    # nil, not []: the merge keeps that item's earlier AI cuisine rows.
    expect(rows_out).to eq(0 => [ { "slug" => "italian", "confidence" => 0.97 } ], 1 => nil)
    expect(logged_line).to include("tagged" => 1, "missing" => 2)
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(described_class::PartialAnswers), hash_including(handled: true))
  end

  # The tagger runs inside GapFillResolveJob between a billed Haiku call
  # and the merge; raising would hand retry_on a reason to re-bill it.
  it "returns nil on an API failure, reports it, and never raises" do
    stub_jev(status: 401, body: { error: "invalid key" })
    allow(Rails.error).to receive(:report)

    result = nil
    expect { result = described_class.new(client: client).call(run, rows) }.not_to raise_error
    expect(result).to be_nil
    expect(Rails.logger).to have_received(:warn).with(/\[jev_cuisine\].*TypesafeClient::ApiError/)
    expect(Rails.error).to have_received(:report).with(an_instance_of(TypesafeClient::ApiError), hash_including(handled: true))
  end
end
