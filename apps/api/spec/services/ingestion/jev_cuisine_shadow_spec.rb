require "rails_helper"

RSpec.describe Ingestion::JevCuisineShadow do
  let(:run) { create(:ingestion_run, :staged, enrichment_status: "pending") }
  let(:client) { TypesafeClient.new(api_key: "test-key", model: "jev-latest") }

  let(:rows) do
    [ { name: "Carbonara", description: "egg, pecorino, guanciale", section: "Pasta" },
     { name: "Carnitas Tacos", description: nil, section: "Tacos" } ]
  end

  let(:haiku_result) do
    { "items" => [
      { "index" => 0, "cuisine_tags" => { "resolved" => [ { "slug" => "italian", "confidence" => 0.9 } ] } },
      { "index" => 1, "cuisine_tags" => { "resolved" => [] } }
    ] }
  end

  # Jev agrees on Carbonara and on "Carbonara is not Mexican", but calls
  # the tacos Mexican where Haiku left them untagged.
  let(:answers) do
    { "i0__italian" => { "type" => "noul", "noul" => 0.97 },
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
    lines = info_lines.grep(/\A\[jev_shadow\] /)
    expect(lines.size).to eq(1)
    JSON.parse(lines.first.delete_prefix("[jev_shadow] "))
  end

  it "counts a Jev-only tag as a disagreement, which is what the trial exists to surface" do
    stub_jev
    described_class.new(client: client).call(run, rows, haiku_result)

    log = logged_line
    expect(log).to include("model" => "jev-1.13.0", "pairs" => 4, "agree" => 3, "jev_only" => 1, "haiku_only" => 0,
                               "missing" => 0)
    expect(log["disagreements"]).to eq(
      [ { "index" => 1, "item" => "Carnitas Tacos", "section" => "Tacos", "tag" => "mexican", "jev" => 0.96, "haiku" => false } ]
    )
  end

  it "asks about leaf cuisines only, with state limited to the dishes themselves" do
    request = stub_jev
    described_class.new(client: client).call(run, rows, haiku_result)

    expect(request.with { |req|
      body = JSON.parse(req.body)
      body["questions"].keys.sort == %w[i0__italian i0__mexican i1__italian i1__mexican] &&
        body["state"] == { "items" => [
          { "name" => "Carbonara", "description" => "egg, pecorino, guanciale", "section" => "Pasta" },
          { "name" => "Carnitas Tacos", "section" => "Tacos" }
        ] }
    }).to have_been_made
  end

  it "counts absent or out-of-range answers as missing instead of letting them pass as agreement" do
    answers.delete("i1__mexican")
    answers["i1__italian"] = { "type" => "noul", "noul" => 1.7 }
    stub_jev
    described_class.new(client: client).call(run, rows, haiku_result)

    expect(logged_line).to include("pairs" => 2, "agree" => 2, "missing" => 2)
  end

  it "treats a dish Haiku returned no row for as missing, not as Haiku saying no" do
    haiku_result["items"].pop
    stub_jev
    described_class.new(client: client).call(run, rows, haiku_result)

    expect(logged_line).to include("pairs" => 2, "agree" => 2, "jev_only" => 0, "missing" => 2)
  end

  # The trial runs inside GapFillResolveJob; an error escaping it would
  # trip the job's retry/failed handling over work nobody depends on.
  it "swallows API failures and logs them instead" do
    stub_jev(status: 401, body: { error: "invalid key" })

    expect { described_class.new(client: client).call(run, rows, haiku_result) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/\[jev_shadow\].*TypesafeClient::ApiError/)
  end
end
