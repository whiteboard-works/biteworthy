require "rails_helper"

# The MCP transport contract: JSON-RPC in, JSON-RPC out, and — the part
# that matters for safety — a tool list that differs by who is asking.
RSpec.describe "POST /mcp", type: :request do
  let(:user)  { create(:user) }
  let(:admin) { create(:user, is_admin: true) }

  def rpc(method, params = {}, headers: {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }.merge(headers)
    response.parsed_body
  end

  def tool_names(headers: {})
    rpc("tools/list", {}, headers: headers).dig("result", "tools").map { |t| t["name"] }
  end

  describe "initialize" do
    it "advertises the server and its instructions" do
      body = rpc("initialize", {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "rspec", version: "1.0" }
      })

      expect(response).to have_http_status(:ok)
      expect(body.dig("result", "serverInfo", "name")).to eq("biteworthy")
      expect(body.dig("result", "instructions")).to include("untrusted")
    end
  end

  describe "tools/list" do
    it "gives anonymous callers the public discovery tools only" do
      names = tool_names

      expect(names).to include("get_menu", "search_restaurants", "search_taxonomy")
      expect(names).not_to include("get_profile", "update_avoid_lists")
    end

    # A listed-but-forbidden tool would still leak that the capability
    # exists and would burn the model's turns discovering it can't call it.
    it "adds the profile tools once a caller is signed in" do
      names = tool_names(headers: auth_headers_for(user))

      expect(names).to include("get_profile", "update_avoid_lists", "set_strictness")
    end

    it "hides admin-only tools from non-admins" do
      admin_only = Tools::Registry.all.select { |t| t.audience == :admin }.map(&:name_value)
      skip "no admin tools registered yet" if admin_only.empty?

      expect(tool_names(headers: auth_headers_for(user))).not_to include(*admin_only)
      expect(tool_names(headers: auth_headers_for(admin))).to include(*admin_only)
    end
  end

  describe "authentication" do
    it "treats a missing Authorization header as anonymous, not an error" do
      expect(tool_names).to be_present
      expect(response).to have_http_status(:ok)
    end

    # Silently downgrading a stale token to anonymous would show the caller
    # someone else's (empty) filter without telling them they're logged out.
    it "401s a bad token rather than falling back to anonymous" do
      rpc("tools/list", {}, headers: { "Authorization" => "Bearer not-a-real-token" })

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include("Bearer")
    end
  end

  describe "tools/call" do
    let!(:city)       { create(:city, slug: "durango") }
    let!(:restaurant) { create(:restaurant, :published, city: city, name: "Ninis Taqueria", slug: "ninis") }

    it "runs a public tool anonymously" do
      body = rpc("tools/call", { name: "get_restaurant", arguments: { restaurant: "ninis" } })

      expect(body.dig("result", "isError")).to be_falsey
      expect(body.dig("result", "structuredContent", "name")).to eq("Ninis Taqueria")
    end

    # The tool was never listed for this caller, so the transport rejects
    # the name outright. The audience check inside Tools::Base is the
    # second line of defence for callers working from a stale tool list —
    # see spec/services/tools/base_spec.rb.
    it "refuses a tool the caller was never offered" do
      body = rpc("tools/call", { name: "get_profile", arguments: {} })

      expect(body.dig("result", "structuredContent")).to be_nil
      expect(body.dig("error", "code")).to eq(-32_602) # JSON-RPC invalid params
    end

    it "reports unknown arguments through the schema rather than 500ing" do
      body = rpc("tools/call", { name: "get_menu", arguments: {} }, headers: auth_headers_for(user))

      expect(body.dig("result", "isError")).to be(true)
      expect(body.dig("result", "content", 0, "text")).to match(/restaurant/i)
    end
  end

  # A prompt argument is a blank box until the server can fill it, and
  # every write path here takes a slug nobody can guess.
  describe "completion/complete" do
    let!(:city) { create(:city, slug: "durango") }
    let!(:ninis) { create(:restaurant, :published, city: city, slug: "ninis-taqueria") }

    def complete(prompt, name, value, headers: {})
      rpc("completion/complete", {
        ref:      { type: "ref/prompt", name: prompt },
        argument: { name: name, value: value }
      }, headers: headers)
    end

    it "advertises that it can answer them" do
      body = rpc("initialize", {
        protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "rspec", version: "1.0" }
      })

      expect(body.dig("result", "capabilities")).to have_key("completions")
    end

    # `listChanged` promises a notification when the catalogue changes,
    # and a stateless transport has no channel to send one on. The lists
    # really do change per caller, which is what makes claiming to
    # announce it worse than saying nothing.
    it "does not promise list-changed notifications it cannot send" do
      body = rpc("initialize", {
        protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "rspec", version: "1.0" }
      })

      expect(body.dig("result", "capabilities", "tools")).not_to include("listChanged")
      expect(body.dig("result", "capabilities", "prompts")).not_to include("listChanged")
    end

    it "completes a restaurant slug for a workflow that takes one" do
      body = complete("scan_a_menu_into_the_database", "restaurant", "nin",
                      headers: auth_headers_for(user))

      expect(body.dig("result", "completion", "values")).to eq(["ninis-taqueria"])
    end

    it "declares the argument on the prompt so a client knows to ask" do
      prompts = rpc("prompts/list", {}, headers: auth_headers_for(user)).dig("result", "prompts")
      scan    = prompts.find { |p| p["name"] == "scan_a_menu_into_the_database" }

      expect(scan["arguments"].map { |a| a["name"] }).to eq(["restaurant"])
      expect(scan["arguments"].first["required"]).to be_falsey
    end

    # The prompt in `ref` is resolved against this caller's own filtered
    # prompt list, so a workflow they cannot run cannot be completed
    # against either — without a second rule here that would drift from
    # the one `WorkflowPrompts.for` already applies.
    it "refuses to complete against a workflow the caller was never offered" do
      body = complete("moderate", "restaurant", "nin")

      expect(body.dig("result", "completion", "values")).to be_nil
      expect(body["error"]).to be_present
    end
  end

  # Completing an argument is only worth anything if what someone picked
  # reaches the conversation. Nothing exercised `prompts/get` before this.
  describe "prompts/get" do
    def rendered(args, headers: auth_headers_for(user))
      body = rpc("prompts/get", { name: "scan_a_menu_into_the_database", arguments: args },
                 headers: headers)
      body.dig("result", "messages", 0, "content", "text")
    end

    it "carries the argument the person filled in" do
      expect(rendered({ restaurant: "ninis-taqueria" })).to include("restaurant: ninis-taqueria")
    end

    # Optional means optional: the workflow has to open for someone who
    # does not yet know which restaurant they mean, and a dangling
    # "What I gave you —" would be the model's first impression.
    it "renders cleanly with nothing filled in" do
      text = rendered({})

      expect(text).to include("Scan a menu into the database")
      expect(text).not_to include("What I gave you")
    end

    it "still names the tool sequence, which is the point of the prompt" do
      expect(rendered({})).to include("create_restaurant → start_menu_scan")
    end
  end

  # The tool map is served as a resource so a client that reads resources
  # learns how the tools compose without spending a turn on a tool call.
  describe "resources" do
    it "advertises the topology" do
      body = rpc("resources/list")

      expect(body.dig("result", "resources").map { |r| r["uri"] }).to include("biteworthy://topology")
    end

    # A menu someone attaches, the way they attach a file — the shape for
    # "here are two menus, help me choose", which is not a thing a model
    # decides to do mid-answer.
    it "offers the menu as a template a client can fill in" do
      body = rpc("resources/templates/list")

      templates = body.dig("result", "resourceTemplates").map { |t| t["uriTemplate"] }
      expect(templates).to include("biteworthy://restaurant/{restaurant}/menu")
    end

    it "reads a restaurant's menu at the filled-in uri" do
      create(:city, slug: "durango").then { |c| create(:restaurant, :published, city: c, slug: "ninis", name: "Ninis Taqueria") }

      body = rpc("resources/read", { uri: "biteworthy://restaurant/ninis/menu" })

      expect(body.dig("result", "contents", 0, "text")).to include("Ninis Taqueria")
    end

    # The variable is named for the same argument the prompts use, so the
    # completion that fills a prompt box fills this one too — one
    # vocabulary rather than two that drift.
    it "completes the template's variable from the same source as a prompt's" do
      city = create(:city, slug: "durango")
      create(:restaurant, :published, city: city, slug: "ninis-taqueria")

      body = rpc("completion/complete", {
        ref:      { type: "ref/resource", uri: "biteworthy://restaurant/{restaurant}/menu" },
        argument: { name: "restaurant", value: "nin" }
      })

      expect(body.dig("result", "completion", "values")).to eq(["ninis-taqueria"])
    end

    it "reads it as markdown, scoped to the caller" do
      body = rpc("resources/read", { uri: "biteworthy://topology" })

      text = body.dig("result", "contents", 0, "text")
      expect(text).to include("## Workflows")
      expect(text).not_to include("moderate_review")
    end

    it "includes the admin workflows for an admin" do
      body = rpc("resources/read", { uri: "biteworthy://topology" }, headers: auth_headers_for(admin))

      expect(body.dig("result", "contents", 0, "text")).to include("moderate_review")
    end
  end

  # A client sees prompts as things a person can pick before typing —
  # "Scan a menu into the database" beats a blank box and forty-four tools.
  describe "prompts/list" do
    def prompts_for(headers)
      post "/mcp",
           params: { jsonrpc: "2.0", id: 1, method: "prompts/list", params: {} }.to_json,
           headers: headers.merge("Content-Type" => "application/json")
      JSON.parse(response.body, symbolize_names: true).dig(:result, :prompts) || []
    end

    it "offers the signed-in workflows to a signed-in caller" do
      names = prompts_for(auth_headers_for(create(:user))).map { |p| p[:name] }

      expect(names).to include("scan_a_menu_into_the_database")
    end

    # Same rule as tools/list: never mention what the caller cannot run.
    it "never mentions an admin workflow to a non-admin" do
      names = prompts_for(auth_headers_for(create(:user))).map { |p| p[:name] }

      expect(names).not_to include("moderate")
    end

    # Derived from the workflows rather than listed, so this asserts the
    # rule ("only what every step is public for") instead of a snapshot
    # of how many workflows happened to qualify the day it was written.
    it "offers an anonymous caller only what is public" do
      names = prompts_for({}).map { |p| p[:name] }
      public_flows = Tools::Topology.for(Tools::Context.new({}))[:workflows]

      expect(names).to match_array(public_flows.map { |f| f[:name].parameterize.underscore })
      expect(names).to include("find_something_this_person_can_eat")
      expect(names).not_to include("moderate")
    end
  end

  # The gate that stops an allergen leaving someone's avoid list without
  # them saying so used to be read only by the chat's agent loop, which
  # made it a property of one front door — this one removed the allergen
  # with nothing asked. A stateless transport cannot stop and ask
  # mid-call, so the refusal carries the sentence and a token instead.
  describe "argument-gated confirmation" do
    let!(:peanut) { create(:ingredient, name: "Peanut", slug: "nut-peanut", path: "nut.peanut") }

    before { user.profile.update!(avoid_ingredient_ids: [peanut.id]) }

    def remove(extra = {})
      rpc("tools/call",
          { name: "update_avoid_lists", arguments: { remove_ingredients: ["nut-peanut"] }.merge(extra) },
          headers: auth_headers_for(user))
    end

    it "refuses the removal first, and says what it needs said" do
      body = remove

      expect(body.dig("result", "isError")).to be(true)
      expect(body.dig("result", "structuredContent", "error")).to eq("confirmation_required")
      expect(body.dig("result", "structuredContent", "prompt")).to include("nut-peanut")
      expect(user.profile.reload.avoid_ingredient_ids).to eq([peanut.id])
    end

    it "goes through on the second call, carrying the token" do
      token = remove.dig("result", "structuredContent", "confirmation_token")

      body = remove(confirmation: token)

      expect(body.dig("result", "isError")).to be_falsey
      expect(user.profile.reload.avoid_ingredient_ids).to be_empty
    end

    # Adding is the safe direction and stays one call — friction there
    # teaches people to click through the prompt they will one day need
    # to actually read.
    it "does not gate an add" do
      body = rpc("tools/call",
                 { name: "update_avoid_lists", arguments: { add_ingredients: ["nut-peanut"] } },
                 headers: auth_headers_for(user))

      expect(body.dig("result", "isError")).to be_falsey
    end
  end

  # Connecting Claude Code today means handing it a JWT carrying every
  # power the account has. A scoped token carries less, and the tool layer
  # is where that is enforced.
  describe "scoped MCP tokens" do
    def rpc(secret, name, arguments = {})
      post "/mcp",
           params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                     params: { name: name, arguments: arguments } }.to_json,
           headers: { "Authorization" => "Bearer #{secret}", "Content-Type" => "application/json" }
      JSON.parse(response.body, symbolize_names: true)
    end

    let!(:city)       { create(:city, slug: "durango") }
    let!(:restaurant) { create(:restaurant, :published, city: city, slug: "ninis") }

    it "authenticates as its owner" do
      user = create(:user)
      _, secret = McpToken.issue!(user: user, name: "Claude Code", scopes: ["discovery:read"])

      body = rpc(secret, "get_restaurant", { restaurant: "ninis" })

      expect(body[:error]).to be_nil
      expect(body.dig(:result, :isError)).to be_falsey
    end

    # The whole point: an admin's read-only token is still an admin's
    # token, and still may not write.
    #
    # The refusal arrives as "no such tool" rather than a scope complaint,
    # because the catalogue is filtered to what the token can use — the
    # same shape an admin-only tool has always had for a non-admin.
    # `Tools::Base#enforce_scope!` is still the boundary underneath; this
    # asserts the two things that matter regardless of which one answers:
    # the write does not happen, and the token was never offered it.
    it "refuses a write the token was not granted, even for an admin" do
      admin = create(:user, is_admin: true)
      _, secret = McpToken.issue!(user: admin, name: "read only", scopes: ["discovery:read"])

      body = rpc(secret, "set_user_role", { user_id: admin.id, is_admin: false })

      post "/mcp",
           params: { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }.to_json,
           headers: { "Authorization" => "Bearer #{secret}", "CONTENT_TYPE" => "application/json" }
      listed = JSON.parse(response.body, symbolize_names: true).dig(:result, :tools).map { |tool| tool[:name] }

      expect(body[:error]).to be_present
      expect(listed).not_to include("set_user_role")
      expect(admin.reload.is_admin).to be(true)
    end

    it "allows the write once the scope is granted" do
      admin = create(:user, is_admin: true)
      other = create(:user)
      _, secret = McpToken.issue!(user: admin, name: "ops", scopes: ["users:write"])

      rpc(secret, "set_user_role", { user_id: other.id, is_admin: true })

      expect(other.reload.is_admin).to be(true)
    end

    # The tool half of the same boundary the REST endpoint holds: the
    # super tier is shell-managed, so a fully-scoped admin token still
    # cannot take it away. The refusal names the rake task rather than
    # just saying no, because the model will otherwise retry.
    it "refuses to demote a super admin even with users:write" do
      admin  = create(:user, is_admin: true)
      target = create(:user, :super_admin)
      _, secret = McpToken.issue!(user: admin, name: "ops", scopes: ["users:write"])

      body = rpc(secret, "set_user_role", { user_id: target.id, is_admin: false })
      text = body.dig(:result, :content, 0, :text).to_s

      expect(text).to include("admin:revoke_super")
      expect(target.reload).to have_attributes(is_admin: true, is_super_admin: true)
    end

    # A revoked credential must stop working without ending every other
    # session the person has.
    it "rejects a revoked token as unauthorized" do
      user = create(:user)
      token, secret = McpToken.issue!(user: user, name: "old laptop")
      token.revoke!

      post "/mcp",
           params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
           headers: { "Authorization" => "Bearer #{secret}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

