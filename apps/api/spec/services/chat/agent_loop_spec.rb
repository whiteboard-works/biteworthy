require "rails_helper"

# A scripted client: each call pops the next canned response, so a
# spec reads as "the model said X, then Y".
class ScriptedClient
  attr_reader :requests, :last_usage

  def initialize(*responses)
    @responses = responses
    @requests  = []
    @last_usage = { "input_tokens" => 100, "output_tokens" => 50 }
  end

  def messages_create(**args)
    @requests << args
    @responses.shift || raise("ScriptedClient ran out of responses after #{@requests.size} calls")
  end

  def system_blocks(*blocks)
    blocks.flatten.map do |b|
      block = { type: "text", text: b.fetch(:text) }
      block[:cache_control] = { type: "ephemeral" } if b[:cache]
      block
    end
  end
end


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

      result = loop_with(say("Deleted.")).run(confirm: true)

      expect(Review.exists?(review.id)).to be(false)
      expect(result.text).to eq("Deleted.")
      expect(conversation.reload.state).to eq("active")
    end

    it "tells the model it was declined, and the review survives" do
      loop_with(delete_call).run(text: "delete my review")

      loop_with(say("Understood, leaving it.")).run(confirm: false)

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
      second = loop_with(say("done")).run(confirm: true)

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
      loop_with(say("done")).run(confirm: true)

      answered = conversation.messages.reload.select(&:tool_result?)
                             .flat_map { |m| m.content.map { |b| b["tool_use_id"] } }
      expect(answered).to contain_exactly("a", "b")
    end
  end

  describe "the request it builds" do
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
    it "puts the one cache breakpoint on the last system block" do
      client = ScriptedClient.new(say("hi"))
      described_class.new(conversation, client: client).run(text: "hello")

      system = client.requests.first[:system]
      expect(system.count { |b| b[:cache_control] }).to eq(1)
      expect(system.last[:cache_control]).to eq({ type: "ephemeral" })
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
end
