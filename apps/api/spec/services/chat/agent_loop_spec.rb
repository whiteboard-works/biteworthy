require "rails_helper"

# ScriptedClient / StreamingScriptedClient live in spec/support — the SSE
# request specs drive the same loop through the controller.

# The chat is the second front door onto the tool layer. These pin the
# properties that make it safe to point a model at real write tools: a
# destructive call waits for a human, every tool_use gets an answer, and
# a conversation cannot spend without limit.
RSpec.describe Chat::AgentLoop do
  let(:user)       { create(:user) }
  let(:conversation) { Conversation.create!(user: user) }
  let!(:city)      { create(:city, slug: "durango", name: "Durango") }
  let!(:restaurant) { create(:restaurant, :published, city: city, name: "Ninis Taqueria", slug: "ninis") }

  def say(text)
    { "stop_reason" => "end_turn", "content" => [{ "type" => "text", "text" => text }] }
  end

  def call_tool(name, input = {}, id: "toolu_1")
    {
      "stop_reason" => "tool_use",
      "content" => [{ "type" => "tool_use", "id" => id, "name" => name, "input" => input }]
    }
  end

  def loop_with(*responses)
    described_class.new(conversation, client: ScriptedClient.new(*responses))
  end

  describe "a plain turn" do
    it "returns the model's text and stores both sides" do
      result = loop_with(say("Hi there.")).run(text: "hello")

      expect(result.text).to eq("Hi there.")
      expect(conversation.messages.pluck(:role)).to eq(%w[user assistant])
    end

    it "gives every message a distinct position" do
      loop_with(say("one")).run(text: "hello")
      loop_with(say("two")).run(text: "again")

      positions = conversation.messages.pluck(:position)
      expect(positions).to eq(positions.uniq.sort)
    end
  end

  describe "read-only tool calls" do
    it "runs them without asking and feeds the result back" do
      client = ScriptedClient.new(
        call_tool("get_restaurant", { "restaurant" => "ninis" }),
        say("Ninis Taqueria is on Main Ave.")
      )

      result = described_class.new(conversation, client: client).run(text: "tell me about ninis")

      expect(result.text).to include("Ninis")
      tool_result = conversation.messages.reload.find(&:tool_result?)
      expect(tool_result.content.first["content"].first["text"]).to include("Ninis Taqueria")
    end

    # The Messages API rejects a transcript where a tool_use has no
    # answer, so a failing tool still has to produce a result block.
    it "answers a tool that errored rather than leaving the call dangling" do
      client = ScriptedClient.new(
        call_tool("get_restaurant", { "restaurant" => "does-not-exist" }),
        say("I couldn't find that one.")
      )

      described_class.new(conversation, client: client).run(text: "find it")

      tool_result = conversation.messages.reload.find(&:tool_result?)
      expect(tool_result.content.first["is_error"]).to be(true)
    end

    it "answers an unknown tool name instead of raising" do
      client = ScriptedClient.new(call_tool("drop_all_tables"), say("I can't do that."))

      described_class.new(conversation, client: client).run(text: "wreck it")

      block = conversation.messages.reload.find(&:tool_result?).content.first
      expect(block["content"].first["text"]).to include("unknown_tool")
    end
  end

  describe "the confirmation gate" do
    let!(:item)   { create(:item, :published, restaurant: restaurant) }
    let!(:review) { create(:review, user: user, item: item, body: "fine") }

    def delete_call
      call_tool("delete_review", { "review_id" => review.id })
    end

    # What a real client does: read the token off the parked call it just
    # drew a prompt for, and hand it back with the answer.
    def parked_fingerprint
      conversation.reload.pending_tool_call.dig("pending", "fingerprint")
    end

    # Nothing that deletes, publishes, or changes what a person is shown
    # runs because a model decided to.
    it "stops before a destructive tool and changes nothing" do
      result = loop_with(delete_call).run(text: "delete my review")

      expect(result).to be_awaiting_confirmation
      expect(result.pending["name"]).to eq("delete_review")
      expect(Review.exists?(review.id)).to be(true)
      expect(conversation.reload.state).to eq("awaiting_confirmation")
    end

    it "runs it once the user says yes" do
      loop_with(delete_call).run(text: "delete my review")

      result = loop_with(say("Deleted.")).run(confirm: true, fingerprint: parked_fingerprint)

      expect(Review.exists?(review.id)).to be(false)
      expect(result.text).to eq("Deleted.")
      expect(conversation.reload.state).to eq("active")
    end

    it "tells the model it was declined, and the review survives" do
      loop_with(delete_call).run(text: "delete my review")

      loop_with(say("Understood, leaving it.")).run(confirm: false, fingerprint: parked_fingerprint)

      expect(Review.exists?(review.id)).to be(true)
      declined = conversation.messages.reload.select(&:tool_result?).last
      expect(declined.content.first["content"].first["text"]).to include("declined")
    end

    it "refuses a new message while a call is parked" do
      loop_with(delete_call).run(text: "delete my review")

      expect { loop_with(say("hi")).run(text: "actually, something else") }
        .to raise_error(ArgumentError, /pending confirmation/)
    end

    # Confirming one destructive call does not pre-authorize the next.
    it "parks again on a second destructive call in the same turn" do
      other = create(:review, user: user, item: create(:item, :published, restaurant: restaurant))
      two_calls = {
        "stop_reason" => "tool_use",
        "content" => [
          { "type" => "tool_use", "id" => "a", "name" => "delete_review", "input" => { "review_id" => review.id } },
          { "type" => "tool_use", "id" => "b", "name" => "delete_review", "input" => { "review_id" => other.id } }
        ]
      }

      loop_with(two_calls).run(text: "delete both")
      second = loop_with(say("done")).run(confirm: true, fingerprint: parked_fingerprint)

      expect(second).to be_awaiting_confirmation
      expect(Review.exists?(review.id)).to be(false)
      expect(Review.exists?(other.id)).to be(true)
    end

    # A read-only call sharing the turn still needs its answer, so its
    # result is parked alongside the queue and replayed on resume.
    it "keeps the safe call's result when it parks the destructive one" do
      mixed = {
        "stop_reason" => "tool_use",
        "content" => [
          { "type" => "tool_use", "id" => "a", "name" => "get_restaurant", "input" => { "restaurant" => "ninis" } },
          { "type" => "tool_use", "id" => "b", "name" => "delete_review", "input" => { "review_id" => review.id } }
        ]
      }

      loop_with(mixed).run(text: "look then delete")
      loop_with(say("done")).run(confirm: true, fingerprint: parked_fingerprint)

      answered = conversation.messages.reload.select(&:tool_result?)
                             .flat_map { |m| m.content.map { |b| b["tool_use_id"] } }
      expect(answered).to contain_exactly("a", "b")
    end
  end

  describe "the request it builds" do
    # Everything up to and including the block carrying the breakpoint.
    def cached_prefix(client)
      system = client.requests.first[:system]
      system[..system.index { |b| b[:cache_control] }].map { |b| b[:text] }.join
    end

    it "offers the caller's tools, not everyone's" do
      client = ScriptedClient.new(say("hi"))
      described_class.new(conversation, client: client).run(text: "hello")

      names = client.requests.first[:tools].map { |t| t[:name] }
      expect(names).to include("get_menu", "get_profile")
      expect(names).not_to include("set_user_role")
    end

    # Tools render into the cached prefix before system, so the single
    # breakpoint belongs on the LAST system block — that caches the tool
    # catalog and the instructions together.
    it "sets exactly one cache breakpoint" do
      client = ScriptedClient.new(say("hi"))
      described_class.new(conversation, client: client).run(text: "hello")

      expect(client.requests.first[:system].count { |b| b[:cache_control] }).to eq(1)
    end

    # The property that matters is not where the breakpoint sits, it is
    # that NOTHING per-request sits above it. A measured 21,650-token
    # cached prefix is thrown away by a single volatile byte in the wrong
    # block, so this compares the prefix across two turns instead of
    # asserting a position.
    it "keeps every byte above the breakpoint identical between turns" do
      first  = ScriptedClient.new(say("one"))
      described_class.new(conversation, client: first).run(text: "hello")
      second = ScriptedClient.new(say("two"))
      described_class.new(conversation, client: second).run(text: "again")

      expect(cached_prefix(second)).to eq(cached_prefix(first))
    end

    # And the volatile block genuinely is volatile — otherwise the split
    # is decoration.
    it "puts the per-turn content below the breakpoint" do
      client = ScriptedClient.new(say("hi"))
      described_class.new(conversation, client: client).run(text: "hello")

      system = client.requests.first[:system]
      breakpoint = system.index { |b| b[:cache_control] }
      expect(system[(breakpoint + 1)..].map { |b| b[:text] }.join).to include("Current time:")
    end

    it "asks for adaptive thinking on the flagship model" do
      client = ScriptedClient.new(say("hi"))
      described_class.new(conversation, client: client).run(text: "hello")

      expect(client.requests.first[:thinking]).to eq({ type: "adaptive" })
      expect(client.requests.first[:model]).to eq("claude-opus-5")
    end

    # A thinking block's signature is rejected if it is rebuilt rather
    # than echoed, so the transcript has to replay verbatim.
    it "replays stored assistant blocks verbatim, including thinking" do
      thinking = { "type" => "thinking", "thinking" => "hmm", "signature" => "sig-abc" }
      client = ScriptedClient.new(
        { "stop_reason" => "end_turn", "content" => [thinking, { "type" => "text", "text" => "ok" }] },
        say("second")
      )
      agent = described_class.new(conversation, client: client)
      agent.run(text: "one")
      described_class.new(conversation, client: client).run(text: "two")

      replayed = client.requests.last[:messages].flat_map { |m| m[:content] }
      expect(replayed).to include(thinking)
    end
  end

  describe "spend limits" do
    it "accrues cost onto the conversation" do
      loop_with(say("hi")).run(text: "hello")

      expect(conversation.reload.api_cost_cents).to be > 0
    end

    it "stops a conversation that has burned its budget" do
      conversation.update!(api_cost_cents: described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT)

      result = loop_with(say("hi")).run(text: "hello")

      expect(result).not_to be_ok
      expect(result.error).to include("spend limit")
    end

    it "stops everyone when the day's budget is gone" do
      Conversation.create!(user: create(:user),
                           api_cost_cents: described_class::DAILY_CEILING_CENTS_DEFAULT)

      result = loop_with(say("hi")).run(text: "hello")

      expect(result.error).to include("daily budget")
    end

    # An admin driving the tools must not be locked out by community spend.
    it "lets an admin through the daily ceiling" do
      Conversation.create!(user: create(:user),
                           api_cost_cents: described_class::DAILY_CEILING_CENTS_DEFAULT)
      admin_conversation = Conversation.create!(user: create(:user, is_admin: true))

      result = described_class.new(admin_conversation, client: ScriptedClient.new(say("hi"))).run(text: "hello")

      expect(result.text).to eq("hi")
    end
  end

  describe "runaway protection" do
    it "gives up rather than looping on a tool forever" do
      calls = Array.new(described_class::MAX_ITERATIONS) { call_tool("get_restaurant", { "restaurant" => "ninis" }) }

      result = loop_with(*calls).run(text: "go")

      expect(result).not_to be_ok
      expect(result.error).to include("Gave up")
    end
  end

  # A turn runs for tens of seconds. Without these events the client can
  # only show a spinner, and the user cannot tell a working scan from a
  # hung one.
  describe "narrating a turn" do
    def events_for(*responses, &run)
      seen = []
      agent = described_class.new(conversation,
                                  client: StreamingScriptedClient.new(*responses),
                                  on_event: ->(payload) { seen << payload })
      (run || ->(a) { a.run(text: "hello") }).call(agent)
      seen
    end

    it "streams the model's words as it writes them" do
      seen = events_for(say("Hello there."))

      expect(seen.select { |e| e[:type] == "text_delta" }.map { |e| e[:text] }).to eq(["Hello ", "there."])
      expect(seen.last).to eq(type: "done", text: "Hello there.")
    end

    it "announces each tool before it runs and reports how it went" do
      seen = events_for(call_tool("get_restaurant", { "restaurant" => "ninis" }), say("On Main Ave."))

      tool_events = seen.select { |e| [:tool_use, :tool_result].include?(e[:type].to_s.to_sym) }
      expect(tool_events.map { |e| [e[:type], e[:name]] })
        .to eq([["tool_use", "get_restaurant"], ["tool_result", "get_restaurant"]])
      expect(tool_events.last[:ok]).to be(true)
    end

    it "reports a failed tool as not ok" do
      seen = events_for(call_tool("get_restaurant", { "restaurant" => "nope" }), say("Couldn't find it."))

      expect(seen.find { |e| e[:type] == "tool_result" }[:ok]).to be(false)
    end

    context "when a destructive tool needs a human" do
      let!(:item)   { create(:item, :published, restaurant: restaurant) }
      let!(:review) { create(:review, user: user, item: item, body: "fine") }

      it "ends the stream on the confirmation rather than on an answer" do
        seen = events_for(call_tool("delete_review", { "review_id" => review.id }))

        expect(seen.last[:type]).to eq("awaiting_confirmation")
        expect(seen.last[:tool]["name"]).to eq("delete_review")
        expect(seen.none? { |e| e[:type] == "tool_use" }).to be(true)
      end
    end

    it "ends on an error event when the budget is gone" do
      conversation.update!(api_cost_cents: described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT)

      seen = events_for(say("hi"))

      expect(seen.last[:type]).to eq("error")
      expect(seen.last[:message]).to include("spend limit")
    end

    # A dropped upstream connection is an outage, not a bug; the user
    # should be told to retry and the conversation must stay usable.
    it "turns an upstream failure into one honest error" do
      client = StreamingScriptedClient.new(AnthropicClient::ApiError.new(status: 529, body: "overloaded"))
      seen   = []
      result = described_class.new(conversation, client: client, on_event: ->(p) { seen << p })
                              .run(text: "hello")

      expect(result).not_to be_ok
      expect(seen.last).to eq(type: "error", message: "The assistant is unavailable right now. Try again in a moment.")
      expect(conversation.reload.state).to eq("active")
    end
  end

  # The gate is only as good as what it is bound to.
  describe "the confirmation binding" do
    let!(:item)   { create(:item, :published, restaurant: restaurant) }
    let!(:review) { create(:review, user: user, item: item, body: "fine") }

    before do
      loop_with(call_tool("delete_review", { "review_id" => review.id })).run(text: "delete my review")
    end

    it "refuses an answer carrying a fingerprint for some other call" do
      result = loop_with(say("done")).run(confirm: true, fingerprint: "not-the-parked-one")

      expect(result.ok?).to be(false)
      expect(Review.exists?(review.id)).to be(true)
      expect(conversation.reload.state).to eq("awaiting_confirmation")
    end

    # Absent must not read as allowed — that is how a check like this
    # quietly stops checking.
    it "refuses an answer carrying no fingerprint at all" do
      result = loop_with(say("done")).run(confirm: true)

      expect(result.ok?).to be(false)
      expect(Review.exists?(review.id)).to be(true)
    end
  end

  # The turn now runs under a lock, and every lifecycle event is a
  # checkpoint. These are the failure modes that had no owner before C3.
  describe "the run lifecycle" do
    # Raises the real Aborted from the real tick, after N checkpoints have
    # passed — so "stop pressed mid-turn" is exercised where it actually
    # lands rather than only before the turn starts.
    def abort_on_tick(after:)
      seen = 0
      allow_any_instance_of(ConversationRun).to receive(:tick!) do
        seen += 1
        raise ConversationRun::Aborted, "stopped" if seen > after

        true
      end
    end

    it "refuses a second turn while one is already answering" do
      ConversationRun.acquire(conversation)

      result = loop_with(say("hi")).run(text: "hello")

      expect(result.ok?).to be(false)
      expect(result.error).to include("already answering")
      expect(conversation.messages.reload).to be_empty
    end

    it "releases the lock when the turn finishes, so the next one can run" do
      loop_with(say("done")).run(text: "hello")

      expect(ConversationRun.running.where(conversation_id: conversation.id)).to be_empty
      expect(loop_with(say("again")).run(text: "and again").ok?).to be(true)
    end

    it "records the token split and the outcome on the run" do
      loop_with(say("done")).run(text: "hello")

      run = ConversationRun.where(conversation_id: conversation.id).last
      expect(run.state).to eq("done")
      expect(run.rounds).to be >= 1
      expect(run.duration_ms).to be >= 0
    end

    it "stops the turn when the flag is already up" do
      abort_on_tick(after: 0)

      result = loop_with(say("unused")).run(text: "keep going")

      expect(result.ok?).to be(false)
      expect(result.error).to include("Stopped")
      expect(ConversationRun.where(conversation_id: conversation.id).last.state).to eq("aborted")
    end

    # The dangerous moment: the model has already asked for a tool, so the
    # stored transcript ends on an unanswered `tool_use`. That is not a
    # lost answer — the Messages API refuses the whole conversation from
    # then on, so the stop has to answer the orphan on its way out.
    it "answers the tool call it abandoned, so the transcript still replays" do
      abort_on_tick(after: 1)

      result = loop_with(call_tool("get_menu", { "restaurant" => "ninis" })).run(text: "what can I eat")

      expect(result.ok?).to be(false)
      answered = conversation.messages.reload.select(&:tool_result?)
                             .flat_map { |m| m.content.map { |b| b["tool_use_id"] } }
      expect(answered).to include("toolu_1")
      expect(conversation.reload.state).to eq("active")
    end

    # And the user has to see it after a reload, not only in the stream
    # they were watching when they pressed the button.
    it "leaves the stop in the record, not just on the wire" do
      abort_on_tick(after: 0)

      loop_with(say("unused")).run(text: "keep going")

      expect(conversation.messages.reload.last.text).to include("Stopped")
    end

    # An assistant turn with no content blocks replays as a 400, so one
    # crashed completion would wedge the conversation rather than costing
    # it a single answer.
    it "prunes an empty assistant message left by a dead turn" do
      conversation.append!(role: "assistant", content: [])

      loop_with(say("fine")).run(text: "hello")

      expect(conversation.messages.reload.none? { |m| m.content == [] }).to be(true)
    end
  end

  # The product's safety claim is that we can always say WHY a dish is
  # hidden. A summary that quietly drops one reads like a good answer, so
  # something other than the author has to look before the user orders.
  describe "the grounding review" do
    let!(:item) { create(:item, :published, restaurant: restaurant, name: "Queso fundido") }

    def reviewing(verdict)
      allow(Chat::GroundingReview).to receive(:new).and_return(
        instance_double(Chat::GroundingReview, call: verdict)
      )
    end

    def flagged(problem) = Chat::GroundingReview::Result.new(grounded: false, problem: problem, checked: true)
    def clean           = Chat::GroundingReview::Result.new(grounded: true, checked: true)

    it "appends a disclaimer to an answer the reviewer flagged" do
      reviewing(flagged("dropped the queso"))

      result = loop_with(call_tool("get_menu", { "restaurant" => "ninis" }), say("Have anything!"))
               .run(text: "what can I eat")

      expect(result.text).to include(Chat::GroundingReview::DISCLAIMER)
      expect(conversation.messages.reload.last.text).to include("hidden for you")
    end

    it "leaves a grounded answer exactly as written" do
      reviewing(clean)

      result = loop_with(call_tool("get_menu", { "restaurant" => "ninis" }), say("The queso is out — dairy."))
               .run(text: "what can I eat")

      expect(result.text).to eq("The queso is out — dairy.")
      expect(result.text).not_to include(Chat::GroundingReview::DISCLAIMER)
    end

    # Only the tools that make a safety claim are worth a second model
    # call — everything else the assistant says is navigation or opinion.
    it "does not review a turn that never touched the filter" do
      expect(Chat::GroundingReview).not_to receive(:new)

      loop_with(call_tool("get_restaurant", { "restaurant" => "ninis" }), say("It is on Main Ave."))
        .run(text: "where is ninis")
    end

    # A flag is a signal worth keeping, not just a disclaimer worth
    # showing.
    it "records the flag on the run" do
      reviewing(flagged("dropped the queso"))
      run = ConversationRun.acquire(conversation)

      described_class.new(conversation, client: ScriptedClient.new(
        call_tool("get_menu", { "restaurant" => "ninis" }), say("Have anything!")
      ), run: run).run(text: "what can I eat")

      expect(run.reload.outcome).to eq("grounding_flagged")
    end
  end
end

