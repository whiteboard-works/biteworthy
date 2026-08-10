require "rails_helper"

# ScriptedClient / StreamingScriptedClient live in spec/support — the SSE
# request specs drive the same loop through the controller.

# The chat is the second front door onto the tool layer. These pin the
# properties that make it safe to point a model at real write tools: a
# destructive call waits for a human, every tool_use gets an answer, and
# a conversation cannot spend without limit.
RSpec.describe Chat::AgentLoop do
  include ActiveSupport::Testing::TimeHelpers

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

  # Spend is stored in micro-cents so a twelve-round turn does not accrue
  # twelve separate round-ups; `api_cost_cents` is a generated column and
  # cannot be written. The ceilings are still declared in cents, so the
  # specs say what they mean and convert at the edge.
  def micro(cents) = cents * 1_000_000

  # Community spend for today, recorded the way it actually happens — on a
  # run. The daily ceiling sums `conversation_runs.cost_micro_cents`, not
  # conversations, so a spec that writes a conversation's total is
  # describing a measure the code no longer uses.
  def spend_today(cents, spender: nil)
    other = Conversation.create!(user: spender || create(:user))
    run   = ConversationRun.acquire(other)
    run.update_columns(cost_micro_cents: micro(cents))
    run.release!(outcome: "done")
    run
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

    # Most of the catalogue is deferred behind tool search, so the model
    # is usually calling a name it read once. Naming the near miss turns
    # a wasted round — or a false "we don't support that" — into a
    # correction the model can act on immediately.
    it "names the near miss when the model typos a tool" do
      client = ScriptedClient.new(call_tool("get_restraunt", { "restaurant" => "ninis" }), say("Here."))

      described_class.new(conversation, client: client).run(text: "tell me about ninis")

      text = conversation.messages.reload.find(&:tool_result?).content.first["content"].first["text"]
      expect(text).to include("Did you mean get_restaurant?")
    end

    # An error string is a channel too. Suggestions are drawn from the
    # tools this caller can see, so a guess that lands near an admin tool
    # gets the generic answer rather than confirmation that it exists.
    it "does not suggest a tool the caller cannot see" do
      client = ScriptedClient.new(call_tool("set_user_roles"), say("Can't."))

      described_class.new(conversation, client: client).run(text: "make me an admin")

      text = conversation.messages.reload.find(&:tool_result?).content.first["content"].first["text"]
      # Not `not_to include("set_user_role")` — the echoed typo contains
      # it as a substring. What must be absent is the suggestion.
      expect(text).not_to include("Did you mean")
      expect(text).to include("tool_search_tool_regex")
    end

    # The suggestion guard is only half of it. Spelled *correctly*, an
    # invisible tool used to come back "You do not have permission to do
    # that" — a scope complaint, which answers the question the name was
    # asking. `docs/mcp.md` promises "not found" instead, and the MCP
    # door already delivers it by resolving against `Registry.for`.
    it "does not confirm an invisible tool exists when named exactly" do
      client = ScriptedClient.new(call_tool("list_users"), say("Can't."))

      described_class.new(conversation, client: client).run(text: "list the users")

      text = conversation.messages.reload.find(&:tool_result?).content.first["content"].first["text"]
      expect(text).to include("unknown_tool")
      expect(text).not_to include("permission")
    end

    # A unit test on `ModePolicy` would not have caught the shape of this
    # one: what made it bad was the blank prompt, and the prompt is read
    # in `park`, one layer up. `accept_edits` used to park on any name it
    # could not look up — which after the visible-set change meant every
    # tool outside the caller's audience, not just a hallucinated one.
    it "does not park a name it cannot look up, even in accept_edits" do
      convo  = Conversation.create!(user: user, chat_mode: "accept_edits")
      client = ScriptedClient.new(call_tool("drop_all_tables"), say("No such thing."))

      result = described_class.new(convo, client: client, mode: "accept_edits").run(text: "go")

      expect(result).not_to be_awaiting_confirmation
      expect(convo.reload.state).to eq("active")
      text = convo.messages.reload.find(&:tool_result?).content.first["content"].first["text"]
      expect(text).to include("unknown_tool")
    end

    # The same conflation in the other direction. Planning refused a name
    # it could not look up, so a *misspelled read* came back as "this
    # write did not run" with an instruction to stop attempting writes
    # for the rest of the turn — the mode's reason attached to the
    # model's typo, and the rest of the turn's tool use talked out of it.
    it "does not call a misspelled read a write in planning mode" do
      convo  = Conversation.create!(user: user, chat_mode: "planning")
      client = ScriptedClient.new(call_tool("get_menuu"), say("Here is the plan."))

      described_class.new(convo, client: client, mode: "planning").run(text: "what can I eat")

      text = convo.messages.reload.find(&:tool_result?).content.first["content"].first["text"]
      expect(text).to include("unknown_tool")
      expect(text).not_to include("planning_mode")
    end

    # The destructive ones leaked through a different door: `decide` runs
    # before `execute`, so the turn parked and asked the person to approve
    # a call that could only have failed — naming the tool in the prompt
    # on the way past.
    it "does not park on an invisible destructive tool" do
      result = loop_with(call_tool("set_user_role", { "user_id" => user.id, "role" => "admin" }),
                         say("Can't.")).run(text: "make me an admin")

      expect(result).not_to be_awaiting_confirmation
      expect(conversation.reload.state).to eq("active")
    end

    it "suggests an admin tool to an admin" do
      admin  = create(:user, is_admin: true)
      convo  = Conversation.create!(user: admin)
      client = ScriptedClient.new(call_tool("set_user_roles"), say("Done."))

      described_class.new(convo, client: client).run(text: "make them an admin")

      text = convo.messages.reload.find(&:tool_result?).content.first["content"].first["text"]
      expect(text).to include("Did you mean set_user_role?")
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

    # `delete_review` is gated by `destructive_hint`, which `Tools::Base`
    # leaves alone. An argument-gated tool is the other half: the loop
    # parks it here, and `Tools::Base` re-checks it on the way through, so
    # approving has to *carry* to the tool rather than being implied by
    # having reached the call. If the grant stopped travelling, the
    # removal would silently not happen and the model would report it did.
    it "carries approval through to an argument-gated tool" do
      peanut = create(:ingredient, name: "Peanut", slug: "nut-peanut", path: "nut.peanut")
      user.profile.update!(avoid_ingredient_ids: [peanut.id])
      remove = call_tool("update_avoid_lists", { "remove_ingredients" => ["nut-peanut"] })

      parked = loop_with(remove).run(text: "stop avoiding peanut")
      expect(parked).to be_awaiting_confirmation
      expect(user.profile.reload.avoid_ingredient_ids).to eq([peanut.id])

      loop_with(say("Done.")).run(confirm: true, fingerprint: parked_fingerprint)

      expect(user.profile.reload.avoid_ingredient_ids).to be_empty
    end

    # `skip_confirmations` has to be honoured in two places, because the
    # chat parks *before* the tool boundary is reached. Missing either one
    # leaves the turn stopped, waiting for an answer the other half would
    # have waved through — so both halves are asserted through a
    # destructive call and an argument-gated one.
    context "when the caller has skip_confirmations set" do
      let(:user) { create(:user, :super_admin) }

      it "runs a destructive tool without parking" do
        result = loop_with(delete_call, say("Deleted.")).run(text: "delete my review")

        expect(result).not_to be_awaiting_confirmation
        expect(result.text).to eq("Deleted.")
        expect(Review.exists?(review.id)).to be(false)
      end

      it "runs an argument-gated avoid-list removal without parking" do
        peanut = create(:ingredient, name: "Peanut", slug: "nut-peanut", path: "nut.peanut")
        user.profile.update!(avoid_ingredient_ids: [peanut.id])
        remove = call_tool("update_avoid_lists", { "remove_ingredients" => ["nut-peanut"] })

        result = loop_with(remove, say("Done.")).run(text: "stop avoiding peanut")

        expect(result).not_to be_awaiting_confirmation
        expect(user.profile.reload.avoid_ingredient_ids).to be_empty
      end

      it "still parks for a super admin who kept the gate on" do
        user.update!(skip_confirmations: false)

        expect(loop_with(delete_call).run(text: "delete my review")).to be_awaiting_confirmation
        expect(Review.exists?(review.id)).to be(true)
      end
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

  # The unit-level statements about each mode are in mode_policy_spec.rb.
  # These are the ones that matter most: that a mode saying no means
  # nothing was written, not merely that a decision came back.
  describe "chat modes" do
    let!(:item)   { create(:item, :published, restaurant: restaurant) }
    let!(:review) { create(:review, user: user, item: item, body: "fine") }
    let!(:peanut) { create(:ingredient, name: "Peanut", slug: "nut-peanut", path: "nut.peanut") }

    def loop_in(mode, *responses)
      described_class.new(conversation, client: ScriptedClient.new(*responses), mode: mode)
    end

    def last_tool_result
      conversation.messages.reload.reverse.find(&:tool_result?).content.first
    end

    describe "planning" do
      let(:add) { call_tool("update_avoid_lists", { "add_ingredients" => ["nut-peanut"] }) }

      it "refuses the write and leaves the profile alone" do
        result = loop_in("planning", add, say("Here is what I would do.")).run(text: "avoid peanut")

        expect(result.text).to eq("Here is what I would do.")
        expect(user.profile.reload.avoid_ingredient_ids).to be_empty
      end

      # The refusal has to reach the model as the tool's own answer, or it
      # spends its remaining rounds retrying the call it cannot make.
      it "tells the model why, as the tool result" do
        loop_in("planning", add, say("Here is the plan.")).run(text: "avoid peanut")

        expect(last_tool_result["is_error"]).to be(true)
        expect(last_tool_result["content"].first["text"]).to include("Planning mode")
      end

      it "still runs a read" do
        client = ScriptedClient.new(call_tool("get_restaurant", { "restaurant" => "ninis" }),
                                    say("It is on Main Ave."))

        described_class.new(conversation, client: client, mode: "planning").run(text: "where is it")

        expect(last_tool_result["is_error"]).to be_falsey
      end

      # A refusal is not a confirmation question, so there is nothing for
      # a standing grant to answer.
      context "when the caller has skip_confirmations set" do
        let(:user) { create(:user, :super_admin) }

        it "refuses the write anyway" do
          loop_in("planning", add, say("Here is the plan.")).run(text: "avoid peanut")

          expect(user.profile.reload.avoid_ingredient_ids).to be_empty
        end
      end
    end

    describe "accept_edits" do
      it "runs an edit that manual would have parked" do
        user.profile.update!(avoid_ingredient_ids: [peanut.id])
        remove = call_tool("update_avoid_lists", { "remove_ingredients" => ["nut-peanut"] })

        result = loop_in("accept_edits", remove, say("Done.")).run(text: "stop avoiding peanut")

        expect(result).not_to be_awaiting_confirmation
        expect(user.profile.reload.avoid_ingredient_ids).to be_empty
      end

      it "still stops before a call no later edit can undo" do
        result = loop_in("accept_edits", call_tool("delete_review", { "review_id" => review.id }))
                 .run(text: "delete my review")

        expect(result).to be_awaiting_confirmation
        expect(Review.exists?(review.id)).to be(true)
      end
    end

    describe "auto" do
      it "runs the destructive call without parking" do
        result = loop_in("auto", call_tool("delete_review", { "review_id" => review.id }), say("Gone."))
                 .run(text: "delete my review")

        expect(result).not_to be_awaiting_confirmation
        expect(Review.exists?(review.id)).to be(false)
      end
    end

    # A mode picked while a turn is in flight belongs to the next turn.
    # The conversation is only the fallback for a caller that names none.
    it "prefers the mode the turn was sent under over the stored one" do
      conversation.update!(chat_mode: "auto")

      result = loop_in("manual", call_tool("delete_review", { "review_id" => review.id }))
               .run(text: "delete my review")

      expect(result).to be_awaiting_confirmation
      expect(Review.exists?(review.id)).to be(true)
    end

    it "falls back to the conversation's mode when the turn names none" do
      conversation.update!(chat_mode: "auto")

      result = loop_with(call_tool("delete_review", { "review_id" => review.id }), say("Gone."))
               .run(text: "delete my review")

      expect(result).not_to be_awaiting_confirmation
      expect(Review.exists?(review.id)).to be(false)
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

    # Tools render into the cached prefix before system, so the system
    # breakpoint belongs on the LAST system block — that caches the tool
    # catalog and the instructions together. Exactly one, because a second
    # one up there would only split a prefix that is already stable.
    it "sets exactly one cache breakpoint in the system prompt" do
      client = ScriptedClient.new(say("hi"))
      described_class.new(conversation, client: client).run(text: "hello")

      expect(client.requests.first[:system].count { |b| b[:cache_control] }).to eq(1)
    end

    # The transcript is the expensive half and was not cached at all: a
    # round adds a few thousand tokens and then pays full input price for
    # all of them again on every later round. A real eleven-round turn
    # billed 167,655 input tokens for a transcript only ever a few
    # thousand tokens long.
    describe "caching the transcript" do
      def blocks_of(request) = request[:messages].flat_map { |m| Array(m[:content]) }

      it "marks the last block so the conversation so far is a cached prefix" do
        client = ScriptedClient.new(say("hi"))
        described_class.new(conversation, client: client).run(text: "hello")

        messages = client.requests.first[:messages]
        expect(Array(messages.last[:content]).last[:cache_control]).to eq({ type: "ephemeral" })
      end

      # One rolling breakpoint, not one per round. Earlier ones stay valid
      # read points on the server, so marking every message would spend
      # breakpoints (there are four) to buy nothing.
      it "marks exactly one block per request, at the end" do
        client = ScriptedClient.new(
          call_tool("get_restaurant", { "restaurant" => "ninis" }), say("done")
        )
        described_class.new(conversation, client: client).run(text: "hello")

        client.requests.each do |request|
          marked = blocks_of(request).select { |b| b.is_a?(Hash) && b[:cache_control] }
          expect(marked.size).to eq(1)
          expect(marked.first).to eq(blocks_of(request).last)
        end
      end

      # The hazard is in-memory, not on disk: `transcript` hands back the
      # loaded records' own jsonb, so marking it in place would leave a
      # stale second breakpoint on every later round of the same turn.
      # Asserting against `messages.reload` would *not* catch that —
      # `append!` only ever creates new rows, so an in-place mutation
      # never reaches Postgres and a database assertion stays green while
      # the bug ships. Check the objects the loop actually reuses.
      it "marks a copy, leaving the transcript it was handed unmarked" do
        client = ScriptedClient.new(say("hi"))
        described_class.new(conversation, client: client).run(text: "hello")

        live = conversation.transcript.flat_map { |m| Array(m[:content]) }
        expect(live.none? { |b| b.is_a?(Hash) && (b[:cache_control] || b["cache_control"]) }).to be(true)
      end

      # The transcript breakpoint's prefix is `tools → system → messages`,
      # so it needs the *whole* system array stable between turns — not
      # just the part above the system breakpoint, which is all the
      # existing prefix spec pins. A per-second timestamp in the volatile
      # block therefore invalidated the transcript cache on every turn:
      # the thing placed below the breakpoint to protect one cache was
      # preventing the other. Bucketing it to the cache's own TTL is what
      # makes cross-turn reuse possible at all.
      # Time is frozen at a known point inside a bucket rather than
      # offset from the wall clock: a relative `travel` straddles a
      # boundary roughly a third of the time, which is a flake, not a
      # finding.
      it "keeps the whole system prompt identical across consecutive turns" do
        travel_to Time.utc(2026, 8, 9, 12, 0, 30) do
          first = ScriptedClient.new(say("one"))
          described_class.new(conversation, client: first).run(text: "hello")

          travel 2.minutes
          second = ScriptedClient.new(say("two"))
          described_class.new(conversation, client: second).run(text: "again")

          expect(second.requests.first[:system]).to eq(first.requests.first[:system])
        end
      end

      # And the bound is real, not a constant pretending to be a clock:
      # past the bucket the prefix moves on, which is fine because the
      # ephemeral cache entry has expired by then anyway.
      it "moves the clock on once the bucket has passed" do
        travel_to Time.utc(2026, 8, 9, 12, 0, 30) do
          first = ScriptedClient.new(say("one"))
          described_class.new(conversation, client: first).run(text: "hello")

          travel 6.minutes
          second = ScriptedClient.new(say("two"))
          described_class.new(conversation, client: second).run(text: "again")

          expect(second.requests.first[:system]).not_to eq(first.requests.first[:system])
        end
      end

      # A thinking block's signature is rejected if it is not replayed
      # byte-identically, so the breakpoint must never land on one. The
      # loop's shape means it currently cannot; the guard is there so a
      # future reordering fails safe instead of 400ing every turn.
      it "leaves a trailing thinking block alone" do
        conversation.append!(role: "user", content: [ { type: "text", text: "hi" } ])
        conversation.append!(
          role: "assistant",
          content: [ { type: "thinking", thinking: "hmm", signature: "sig" } ]
        )
        loop_instance = described_class.new(conversation, client: ScriptedClient.new(say("ok")))

        turns = loop_instance.send(:cacheable, conversation.transcript)

        expect(turns.last[:content].last).not_to have_key(:cache_control)
      end
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
    # Asserted in micro-cents, which is where the money now lives.
    # `api_cost_cents` legitimately reads 0 for a turn this small — it is
    # a rounded view, and a sub-half-cent turn really did cost about
    # nothing. That it *used* to read 1¢ per call is the bug, not the
    # baseline.
    it "accrues cost onto the conversation" do
      loop_with(say("hi")).run(text: "hello")

      expect(conversation.reload.api_cost_micro_cents).to be > 0
    end

    # The whole reason for the micro-cent column. `.cents` rounds up per
    # call, so twelve rounds of a sub-cent call used to bill 12¢ against
    # a 200¢ ceiling for tokens worth a fraction of that.
    it "does not round up once per round" do
      tiny = { "input_tokens" => 10, "output_tokens" => 2 }
      client = ScriptedClient.new(
        *Array.new(3) { call_tool("get_restaurant", { "restaurant" => "ninis" }) }, say("done")
      )
      allow(client).to receive(:last_usage).and_return(tiny)

      described_class.new(conversation, client: client).run(text: "hello")

      # Four calls at 10×500 + 2×2500 = 10,000 micro-cents each.
      expect(conversation.reload.api_cost_micro_cents).to eq(4 * 10_000)
      # Under a cent in total, where per-call rounding would have said 4¢.
      expect(conversation.api_cost_cents).to eq(0)
    end

    it "stops a conversation that has burned its budget" do
      conversation.update!(api_cost_micro_cents: micro(described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT))

      result = loop_with(say("hi")).run(text: "hello")

      expect(result).not_to be_ok
      expect(result.error).to include("of its #{described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT}¢ limit")
    end

    # The daily wall counts runs, not conversations. Charging a
    # conversation's lifetime spend to its creation date meant a chat
    # opened yesterday and continued today contributed nothing — and with
    # a $10 per-conversation ceiling that is a $10 hole per long-lived
    # conversation, in a product whose chats are meant to outlive a
    # session.
    it "counts today's spend from a conversation opened yesterday" do
      old = nil
      travel_to 2.days.ago do
        old = Conversation.create!(user: create(:user))
      end
      run = ConversationRun.acquire(old)
      run.record_round!({ "cache_creation_input_tokens" => 8_000_000 },
                        model: described_class::MODEL)
      run.release!(outcome: "done")

      result = loop_with(say("hi")).run(text: "hello")

      expect(result.error).to include("daily budget")
    end

    it "stops everyone when the day's budget is gone" do
      spend_today(described_class::DAILY_CEILING_CENTS_DEFAULT)

      result = loop_with(say("hi")).run(text: "hello")

      expect(result.error).to include("daily budget")
    end

    # The ceiling is "$50/day across all non-admin chat" and admins are
    # exempt from the check — so counting their spend in the sum let an
    # operator driving the tools for an afternoon lock out every ordinary
    # user while staying exempt themselves. Exempt from a ceiling and
    # able to fill it is the wrong pair.
    it "does not let an admin's own spend exhaust the community budget" do
      spend_today(described_class::DAILY_CEILING_CENTS_DEFAULT, spender: create(:user, :admin))

      result = loop_with(say("hi")).run(text: "hello")

      expect(result.text).to eq("hi")
    end

    # An admin driving the tools must not be locked out by community spend.
    it "lets an admin through the daily ceiling" do
      spend_today(described_class::DAILY_CEILING_CENTS_DEFAULT)
      admin_conversation = Conversation.create!(user: create(:user, is_admin: true))

      result = described_class.new(admin_conversation, client: ScriptedClient.new(say("hi"))).run(text: "hello")

      expect(result.text).to eq("hi")
    end

    # The per-conversation ceiling is checked *above* the admin return, so
    # an admin has always hit it. That is the gap the super tier closes —
    # and the reason it is a separate bit: any admin can promote another
    # admin over HTTP, so if plain admin cleared the ceilings, one
    # promotion would hand out an uncapped bill.
    it "still stops an admin at the per-conversation ceiling" do
      admin_conversation = Conversation.create!(
        user: create(:user, :admin),
        api_cost_micro_cents: micro(described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT)
      )

      result = described_class.new(admin_conversation, client: ScriptedClient.new(say("hi")))
                              .run(text: "hello")

      expect(result).not_to be_ok
      expect(result.error).to include("of its #{described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT}¢ limit")
    end

    it "lets a super admin through the per-conversation ceiling" do
      super_conversation = Conversation.create!(
        user: create(:user, :super_admin),
        api_cost_micro_cents: micro(described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT * 10)
      )

      result = described_class.new(super_conversation, client: ScriptedClient.new(say("hi")))
                              .run(text: "hello")

      expect(result.text).to eq("hi")
    end

    it "lets a super admin through the daily ceiling" do
      spend_today(described_class::DAILY_CEILING_CENTS_DEFAULT)
      super_conversation = Conversation.create!(user: create(:user, :super_admin))

      result = described_class.new(super_conversation, client: ScriptedClient.new(say("hi")))
                              .run(text: "hello")

      expect(result.text).to eq("hi")
    end

    # The refusal is what someone reads when the chat stops working, so
    # it says which ceiling and how far past it — "start a new one" alone
    # does not tell you whether to wait, raise the cap, or look for a
    # runaway.
    it "names the ceiling and the spend in the refusal" do
      conversation.update!(api_cost_micro_cents: micro(described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT + 3))

      result = loop_with(say("hi")).run(text: "hello")

      expect(result.error).to include((described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT + 3).to_s)
      expect(result.error).to include(described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT.to_s)
    end

    # Deliberately no spec for "the refusal reports a stale figure".
    # Review raised it and it is a real latent inconsistency — `increment!`
    # refreshes only the column it incremented, and `api_cost_cents` is
    # generated — but it is not reachable: `append!` takes `with_lock`
    # before every `call_model`, and that reloads the row. A spec written
    # for it passes with the bug in place, which is worse than no spec.
    # The message reads from the same column the guard compares anyway,
    # so the two cannot drift if that reload ever goes away.
    it "accrues cost onto the run as well as the conversation" do
      loop_with(say("hi")).run(text: "hello")

      run = ConversationRun.where(conversation_id: conversation.id).last
      expect(run.cost_micro_cents).to be > 0
      expect(run.cost_micro_cents).to eq(conversation.reload.api_cost_micro_cents)
    end
  end

  describe "runaway protection" do
    it "gives up rather than looping on a tool forever" do
      calls = Array.new(described_class::MAX_ITERATIONS) { call_tool("get_restaurant", { "restaurant" => "ninis" }) }

      result = loop_with(*calls).run(text: "go")

      expect(result).not_to be_ok
      expect(result.error).to include("#{described_class::MAX_ITERATIONS} steps")
    end

    # The wall is only half the job. Returning a bare error `Result` told
    # the person watching and nobody else: the reason lived in an SSE
    # event, and `Chat::Serializer` builds a conversation from `messages`,
    # so a reload showed their own question with nothing after it.
    it "leaves the reason in the transcript, not just the stream" do
      calls = Array.new(described_class::MAX_ITERATIONS) { call_tool("get_restaurant", { "restaurant" => "ninis" }) }

      loop_with(*calls).run(text: "go")

      last = conversation.messages.reload.last
      expect(last.role).to eq("assistant")
      expect(last.content.first["text"]).to include("#{described_class::MAX_ITERATIONS} steps")
    end

    # MAX_ITERATIONS bounds rounds, not time. A round may sit for the full
    # upstream read timeout while `tick!` keeps renewing the lease, so a
    # dozen slow ones hold a conversation for the better part of an hour
    # and look healthy the whole way.
    describe "the turn deadline" do
      include ActiveSupport::Testing::TimeHelpers

      after { travel_back }

      def slow_client(*responses, streaming: false)
        client = (streaming ? StreamingScriptedClient : ScriptedClient).new(*responses)
        method = streaming ? :messages_stream : :messages_create
        allow(client).to receive(method).and_wrap_original do |original, *args, **kwargs, &block|
          travel(described_class::TURN_DEADLINE_SECONDS_DEFAULT + 1)
          original.call(*args, **kwargs, &block)
        end
        client
      end

      # Checked between rounds, so the round that overran still finished
      # answering its own tool calls. A raise here would leave the
      # transcript ending on an unanswered `tool_use`, which the Messages
      # API rejects from then on — the conversation would be dead, not
      # merely one answer poorer.
      it "stops between rounds, with every tool call still answered" do
        client = slow_client(call_tool("get_menu", { "restaurant" => "ninis" }), say("never reached"))

        result = described_class.new(conversation, client: client).run(text: "what can I eat")

        expect(result).not_to be_ok
        expect(result.error).to include("too long")
        expect(client.requests.size).to eq(1)
        answered = conversation.messages.reload.select(&:tool_result?)
                               .flat_map { |m| m.content.map { |b| b["tool_use_id"] } }
        expect(answered).to include("toolu_1")
      end

      # The user has to find out from a reload, not only from the stream
      # they happened to be watching — and the run has to say why it ended
      # so a slow turn is distinguishable from one somebody stopped.
      it "leaves the conversation usable and names the outcome on the run" do
        described_class.new(conversation, client: slow_client(call_tool("get_menu", { "restaurant" => "ninis" })))
                       .run(text: "what can I eat")

        expect(conversation.reload.state).to eq("active")
        expect(conversation.messages.last.text).to include("too long")
        run = ConversationRun.where(conversation_id: conversation.id).last
        expect(run.state).to eq("failed")
        expect(run.outcome).to eq("timed_out")
      end

      it "sends exactly one terminal event, not one per path that ended the turn" do
        seen = []
        described_class.new(conversation,
                            client: slow_client(call_tool("get_menu", { "restaurant" => "ninis" }), streaming: true),
                            on_event: ->(payload) { seen << payload }).run(text: "what can I eat")

        expect(seen.count { |e| %w[done error awaiting_confirmation].include?(e[:type].to_s) }).to eq(1)
      end
    end
  end

  # The system prompt, the tool catalog, and the caller's profile snapshot
  # are constant for the life of a turn — and they are exactly the bytes
  # the prompt cache is keyed on. Rebuilding them for each of up to twelve
  # rounds re-rendered 44 JSON schemas, walked the registry three more
  # times, and went back to Postgres for a profile, to arrive at the same
  # answer.
  describe "the per-turn setup" do
    def three_round_turn
      client = ScriptedClient.new(
        call_tool("get_restaurant", { "restaurant" => "ninis" }, id: "a"),
        call_tool("get_restaurant", { "restaurant" => "ninis" }, id: "b"),
        say("On Main Ave.")
      )
      described_class.new(conversation, client: client).run(text: "look twice")
      client
    end

    it "builds the system prompt and the tool catalog once, whatever the round count" do
      allow(Chat::SystemPrompt).to receive(:new).and_call_original
      allow(Chat::ToolCatalog).to receive(:definitions).and_call_original

      client = three_round_turn

      expect(client.requests.size).to eq(3)
      expect(Chat::SystemPrompt).to have_received(:new).once
      expect(Chat::ToolCatalog).to have_received(:definitions).once
    end

    # Equal is not enough: the cache is keyed on bytes, and a rebuild that
    # happened to agree would still be a rebuild waiting for the first
    # per-round value to leak into it.
    it "sends the identical system blocks and tools on every round" do
      client = three_round_turn

      expect(client.requests.map { |r| r[:system] }.uniq.size).to eq(1)
      expect(client.requests.map { |r| r[:tools] }.uniq.size).to eq(1)
    end

    # The aggregate is over `conversation_runs` now — spend incurred
    # today, rather than the lifetime spend of conversations created
    # today — but it is still read once per turn, not once per round.
    it "reads the day's spend once, not once per round" do
      queries = capture_sql { three_round_turn }

      expect(queries.grep(/SUM\("conversation_runs"\."cost_micro_cents"\)/).size).to eq(1)
    end

    # The transcript only grows by messages this loop wrote itself, so
    # re-reading every jsonb blob each round — thinking blocks, signatures
    # and all — was O(rounds²) bytes for nothing.
    it "loads the stored transcript once, not once per round" do
      queries = capture_sql { three_round_turn }

      expect(queries.grep(/SELECT "messages"\.\* FROM "messages"/).size).to eq(1)
    end

    # The snapshot is deliberately a snapshot: the prompt tells the model
    # to trust a tool's response over it when the profile changes mid-turn.
    it "reads the caller's profile once, not once per round" do
      peanut = create(:ingredient, name: "Peanut", slug: "nut-peanut", path: "nut.peanut")
      user.profile.update!(avoid_ingredient_ids: [peanut.id])

      queries = capture_sql { three_round_turn }

      expect(queries.grep(/FROM "ingredients"/).size).to eq(1)
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
      conversation.update!(api_cost_micro_cents: micro(described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT))

      seen = events_for(say("hi"))

      expect(seen.last[:type]).to eq("error")
      expect(seen.last[:message]).to include("of its #{described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT}¢ limit")
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

  # Every way a turn can end has to leave the same thing behind: a
  # sentence the person still sees after a reload. The stream is a view —
  # `Chat::Serializer` builds a conversation from `messages` — so a turn
  # that ends with an event and no message reads, on the next page load,
  # as a question nobody ever answered.
  #
  # Not an alternation fix. A probe against `claude-opus-5` confirms the
  # Messages API accepts consecutive same-role messages; what it refuses
  # is a transcript *ending* on an assistant turn, which `repair_for`
  # already covers. This is about what the person is left looking at.
  describe "what a failed turn leaves behind" do
    def last_assistant_text
      last = conversation.messages.reload.last
      last.role == "assistant" ? last.content.first["text"] : nil
    end

    it "writes down a budget refusal" do
      conversation.update!(api_cost_micro_cents: micro(described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT))

      loop_with(say("hi")).run(text: "hello")

      expect(last_assistant_text).to include("of its #{described_class::PER_CONVERSATION_CEILING_CENTS_DEFAULT}¢ limit")
    end

    it "writes down an upstream failure" do
      client = StreamingScriptedClient.new(AnthropicClient::ApiError.new(status: 529, body: "overloaded"))

      described_class.new(conversation, client: client).run(text: "hello")

      expect(last_assistant_text).to include("unavailable right now")
    end

    # The floor, for an exception nobody named. Since #583 the client's
    # stream closes on its own once the run is released — so without a
    # message and a terminal event it closes on silence, and the turn
    # simply stops mid-air.
    it "apologises for a crash rather than vanishing" do
      client = StreamingScriptedClient.new(RuntimeError.new("boom"))
      seen   = []

      result = described_class.new(conversation, client: client, on_event: ->(p) { seen << p }).run(text: "hello")

      expect(result).not_to be_ok
      expect(last_assistant_text).to include("something went wrong")
      expect(seen.count { |e| e[:type] == "error" }).to eq(1)
    end

    # Crashing out of a *parked* turn is the case with teeth. `halt`
    # clears `state` and `pending_tool_call`; without that the
    # conversation stays awaiting an answer to a call that will never
    # run, and every later message raises "answer the pending
    # confirmation first" — locked out by the gate meant to protect them.
    it "leaves a parked conversation usable after a crash" do
      item   = create(:item, :published, restaurant: restaurant)
      review = create(:review, user: user, item: item, body: "fine")
      loop_with(call_tool("delete_review", { "review_id" => review.id })).run(text: "delete my review")
      expect(conversation.reload.state).to eq("awaiting_confirmation")

      fingerprint = conversation.pending_tool_call.dig("pending", "fingerprint")
      allow(Tools::Registry).to receive(:find).and_raise(RuntimeError, "boom")
      described_class.new(conversation, client: StreamingScriptedClient.new)
                     .run(confirm: true, fingerprint: fingerprint)

      expect(conversation.reload.state).to eq("active")
      expect(conversation.pending_tool_call).to be_nil

      allow(Tools::Registry).to receive(:find).and_call_original
      result = loop_with(say("second time lucky")).run(text: "again")
      expect(result).to be_ok
      expect(result.text).to eq("second time lucky")
    end

    # `answer_orphans!` is the model's memory of the turn, not the user's.
    # A call that never ran because someone hit stop and one that never
    # ran because we crashed are different facts, and answering both with
    # "stopped" teaches the next turn to mis-plan.
    #
    # An orphan needs the turn to die *between* storing the call and
    # storing its result, which rules out most of the early exits: the
    # budget check, the deadline check and the upstream call all sit at
    # the top of a round, by which point the previous round's results are
    # already written. Stop is one real producer (`tick!` runs inside
    # `execute`); a raise in the queue walk is the other.
    #
    # Stubbing `Tools::Base.call` itself is the stable way to stage that.
    # It is the rescue wrapper, so replacing it models the one failure it
    # cannot contain — a bug in the boundary rather than in a tool. An
    # earlier version stubbed `Registry.find` and quietly stopped raising
    # when the loop moved to resolving through `Registry.for`: the spec
    # kept passing the wrong thing rather than failing.
    it "tells the model why a call never ran" do
      allow(Tools::Discovery::GetRestaurant).to receive(:call).and_raise(RuntimeError, "boom")

      described_class.new(
        conversation,
        client: StreamingScriptedClient.new(call_tool("get_restaurant", { "restaurant" => "ninis" }))
      ).run(text: "go")

      orphan = conversation.messages.reload.select(&:tool_result?).last
      expect(orphan.content.first["content"].first["text"]).to include("failed before this ran")
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

