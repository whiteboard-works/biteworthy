require "rails_helper"

# The LLM is an untrusted caller, and this asserts that over the REAL
# catalog rather than a fixture tool.
#
# The bug this file exists to prevent is not "a tool mishandles bad input" —
# it is that the two front doors handled it differently. The MCP server
# validated arguments against the schema; the chat's agent loop called
# `tool.call` directly and validated nothing, so an invented argument name
# raised `ArgumentError: unknown keyword` and reached the model as
# "cannot be retried" — telling it to give up on a mistake it could have
# fixed in one round.
#
# So the invariants are asserted through BOTH doors: `Tools::Base.call`
# (what the chat loop uses) and `POST /mcp` (what Claude Desktop uses).
RSpec.describe "malformed tool calls" do
  # Signed-in and admin so no tool short-circuits on audience before it
  # reaches argument validation — the point is to exercise the validation.
  let(:user) { create(:user, is_admin: true) }
  let(:server_context) { { user_id: user.id } }

  def payload(response)
    JSON.parse(response.to_h[:content].first[:text], symbolize_names: true)
  end

  describe "through Tools::Base (the chat loop's door)" do
    Tools::Registry.all.each do |tool|
      context tool.name_value do
        it "rejects an argument name it invented" do
          response = tool.call(server_context: server_context, definitely_not_a_real_argument: "x")

          expect(response.to_h[:isError]).to be(true)
          expect(payload(response)[:error]).to eq("invalid_argument")
          # Naming the accepted arguments is what makes it self-correcting
          # rather than just a rejection.
          expect(payload(response)[:message]).to include("definitely_not_a_real_argument")
        end

        it "never raises on an empty call" do
          expect { tool.call(server_context: server_context) }.not_to raise_error
        end

        it "never raises when every declared argument is the wrong type" do
          args = tool.input_schema_value.to_h[:properties].to_h.keys.to_h { |key| [key.to_sym, []] }

          expect { tool.call(server_context: server_context, **args) }.not_to raise_error
        end
      end
    end
  end

  describe "through POST /mcp (the Claude client's door)", type: :request do
    let(:headers) { { "Authorization" => "Bearer #{Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first}" } }

    def rpc(name, arguments)
      post "/mcp",
           params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                     params: { name: name, arguments: arguments } }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      JSON.parse(response.body, symbolize_names: true)
    end

    it "answers an invented argument with a tool error, not a protocol error" do
      body = rpc("get_profile", { definitely_not_a_real_argument: "x" })

      expect(body[:error]).to be_nil, "expected a tool-level error the model can recover from"
      expect(body.dig(:result, :isError)).to be(true)
    end

    it "answers a tool that raises with a tool error, not a 500" do
      allow(Tools::Profile::GetProfile).to receive(:perform).and_raise(TypeError, "genuine bug")

      body = rpc("get_profile", {})

      expect(response).to have_http_status(:ok)
      expect(body[:error]).to be_nil
      expect(body.dig(:result, :isError)).to be(true)
    end
  end

  # Before C1 this raised out of `Tools::Base.call`, and only the chat loop's
  # own rescue stopped it killing a turn. The boundary is the tool now, so
  # the loop was able to drop that rescue — this is what holds it up.
  it "contains a tool bug rather than letting it reach the caller" do
    allow(Tools::Discovery::SearchRestaurants).to receive(:perform).and_raise(TypeError, "genuine bug")

    response = Tools::Discovery::SearchRestaurants.call(server_context: server_context, query: "taco")

    expect(response.to_h[:isError]).to be(true)
    expect(payload(response)[:error]).to eq("tool_failed")
  end
end
