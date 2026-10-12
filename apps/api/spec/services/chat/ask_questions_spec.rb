require "rails_helper"

# The second parked state.
#
# What it is for is narrow and worth keeping in view: a model that is
# unsure can always *write* "did you mean the taqueria or the cantina?"
# and wait. What comes back is a string — "the first one", "taqueria",
# "yes" — and every call after that rests on the model having read it the
# way the person meant. Here the options are written down by the server,
# the client draws exactly those, and what returns is an **option id**.
# These pin that property rather than the plumbing.
RSpec.describe "Chat::AgentLoop asking a question" do
  let(:user)         { create(:user) }
  let(:conversation) { Conversation.create!(user: user) }

  def ask(question: "Which Nini's did you mean?", options: nil)
    options ||= [ { "id" => "taqueria", "label" => "Nini's Taqueria" },
                  { "id" => "cantina",  "label" => "Nini's Cantina" } ]
    { "type" => "tool_use", "id" => "call-1", "name" => "ask_questions",
      "input" => { "question" => question, "options" => options } }
  end

  def turn(*blocks) = { "content" => blocks, "stop_reason" => "tool_use" }
  def said(text)    = { "content" => [ { "type" => "text", "text" => text } ], "stop_reason" => "end_turn" }

  # The `tool_result` the model is handed for the parked call — which is
  # the person's answer, and the whole point of the round trip.
  def answered_text(client)
    block = client.requests.first[:messages].flat_map { |m| Array(m[:content]) }
                  .find { |b| (b["type"] || b[:type]) == "tool_result" }
    Array(block["content"] || block[:content]).map { |c| c["text"] || c[:text] }.join
  end

  def run_with(*responses, **args)
    client = ScriptedClient.new(*responses)
    result = Chat::AgentLoop.new(conversation, client: client).run(**args)
    [ result, client ]
  end

  describe "parking" do
    it "stops the turn and stores the options the person will answer" do
      result, client = run_with(turn(ask), said("unreachable"), text: "what can I eat at ninis")

      expect(result.state).to eq(:awaiting_answers)
      expect(conversation.reload.state).to eq("awaiting_answers")
      expect(conversation.pending_questions["question"]).to eq("Which Nini's did you mean?")
      expect(conversation.pending_questions["options"].map { |o| o["id"] }).to eq(%w[taqueria cantina])
      # The halt is the point: the model does not get a second round to
      # answer around the question it just asked.
      expect(client.requests.size).to eq(1)
    end

    # The tool never runs. Parking happens on the decision to call it,
    # exactly like a confirmation, because this call's `tool_result` has
    # to be the person's answer and so must not already exist.
    it "does not dispatch the tool" do
      allow(Tools::Meta::AskQuestions).to receive(:perform)

      run_with(turn(ask), text: "what can I eat")

      expect(Tools::Meta::AskQuestions).not_to have_received(:perform)
    end

    it "tells the client what to draw" do
      seen = []
      # Streaming, because `on_event` is what switches the loop onto
      # `messages_stream` — a plain ScriptedClient has no such method and
      # the turn dies in the crash floor instead of parking.
      Chat::AgentLoop.new(conversation, client: StreamingScriptedClient.new(turn(ask)),
                                        on_event: ->(e) { seen << e }).run(text: "hi")

      terminal = seen.find { |e| e[:type] == "awaiting_answers" }
      expect(terminal[:question]["question"]).to eq("Which Nini's did you mean?")
      expect(terminal[:question]["options"].map { |o| o["label"] })
        .to eq([ "Nini's Taqueria", "Nini's Cantina" ])
      expect(terminal[:question]["fingerprint"]).to be_present
    end

    # A parked conversation nobody can un-park needs a human with database
    # access to clear, so a malformed question has to come back as
    # something the model can fix on its next round instead.
    it "refuses a question with one option rather than parking on it" do
      one = [ { "id" => "only", "label" => "The only one" } ]
      result, = run_with(turn(ask(options: one)), said("Sorry — which did you mean?"),
                         text: "what can I eat")

      expect(result.state).to eq(:done)
      expect(conversation.reload.state).to eq("active")
      expect(conversation.messages.map(&:content).flatten.to_s).to include("two to five options")
    end

    # This path bypasses `Tools::Base.call` and so the input-schema
    # validator with it, which makes the element type our problem: a
    # crashed turn is a much worse answer than "fix your arguments".
    it "refuses a malformed option rather than crashing the turn" do
      result, = run_with(turn(ask(options: [ nil, { "id" => "b", "label" => "B" } ])),
                         said("let me try that again"), text: "hi")

      expect(result.state).to eq(:done)
      expect(conversation.reload.state).to eq("active")
    end

    it "refuses options that share an id" do
      same = [ { "id" => "a", "label" => "One" }, { "id" => "a", "label" => "Two" } ]
      result, = run_with(turn(ask(options: same)), said("let me try again"), text: "hi")

      expect(result.state).to eq(:done)
      expect(conversation.reload.state).to eq("active")
    end

    it "refuses more than five options" do
      six = (1..6).map { |n| { "id" => "o#{n}", "label" => "Option #{n}" } }
      result, = run_with(turn(ask(options: six)), said("let me narrow that down"), text: "hi")

      expect(result.state).to eq(:done)
      expect(conversation.reload.state).to eq("active")
    end

    # The schema is not applied on this path, so a numeric id arrives as a
    # number. The client posts it back as a string, and an id that cannot
    # match its own button is a question nobody can answer.
    it "stores option ids as strings so a numeric id can still be picked" do
      numeric = [ { "id" => 1, "label" => "One", "detail" => 2 }, { "id" => 2, "label" => "Two" } ]
      run_with(turn(ask(options: numeric)), text: "hi")

      stored = conversation.reload.pending_questions["options"]
      expect(stored.map { |o| o["id"] }).to eq(%w[1 2])
      expect(stored.first["detail"]).to eq("2")

      _, client = run_with(said("One it is."), answer: { "option_id" => "1" },
                           fingerprint: conversation.pending_questions["fingerprint"])
      expect(answered_text(client)).to include("\"option_id\": \"1\"")
    end

    # Every call behind the question was decided before the model had the
    # answer. Running it after the answer, as a confirmation does, would
    # let a write go through against the guess the question exists to
    # avoid — so each is answered as skipped and nothing is dispatched.
    it "does not run the calls queued behind the question, before or after the answer" do
      allow(Tools::Meta::DescribeCapabilities).to receive(:perform)
      later = { "type" => "tool_use", "id" => "call-2", "name" => "describe_capabilities", "input" => {} }

      run_with(turn(ask, later), text: "hi")
      expect(conversation.reload.state).to eq("awaiting_answers")

      _, client = run_with(said("The taqueria then."), answer: { "option_id" => "taqueria" },
                           fingerprint: conversation.pending_questions["fingerprint"])

      expect(Tools::Meta::DescribeCapabilities).not_to have_received(:perform)
      results = client.requests.first[:messages].flat_map { |m| Array(m[:content]) }
                      .select { |b| (b["type"] || b[:type]) == "tool_result" }
      expect(results.size).to eq(2)
      expect(results.map { |b| (b["content"] || b[:content]).to_s }.join).to include("skipped")
    end

    # Same question, same options, asked twice: a tab still showing the
    # first must not be able to answer the second.
    it "gives the same question a different fingerprint each time it is asked" do
      run_with(turn(ask), text: "hi")
      first = conversation.reload.pending_questions["fingerprint"]
      run_with(said("ok"), answer: { "text" => "neither" }, fingerprint: first)
      run_with(turn(ask), text: "try again")

      expect(conversation.reload.pending_questions["fingerprint"]).not_to eq(first)
    end
  end

  # The narrower race the controller cannot see. It refuses a message
  # sent *at* a parked conversation, but a message can arrive while the
  # turn is still running and only then does the turn park. `AgentLoop`
  # treats a message in that state as a caller bug and re-raises, so the
  # job would go down and take the message with it.
  describe "a message queued just before the park" do
    before { run_with(turn(ask), text: "what can I eat at ninis") }

    it "holds it rather than losing it with the job" do
      expect(conversation.reload.state).to eq("awaiting_answers")
      conversation.enqueue_turn!("kind" => "message", "text" => "actually, never mind")

      expect {
        Chat::CompletionJob.new.perform(conversation.id)
      }.not_to raise_error

      expect(conversation.reload.pending_turns.first["text"]).to eq("actually, never mind")
    end

    # The answer is appended *behind* the held message. Popping the head
    # would hand back the message, hold it again, and never reach the
    # answer — a parked conversation nobody could un-park from the client.
    # The reply runs first, then the message it was holding up.
    it "runs the answer queued behind it, then the held message" do
      fingerprint = conversation.reload.pending_questions["fingerprint"]
      conversation.enqueue_turn!("kind" => "message", "text" => "actually, never mind", "mode" => "manual")
      conversation.enqueue_turn!("kind" => "answer", "option_id" => "taqueria",
                                 "fingerprint" => fingerprint, "mode" => "manual")
      allow(AnthropicClient).to receive(:new)
        .and_return(StreamingScriptedClient.new(said("The taqueria it is."), said("No problem.")))

      Chat::CompletionJob.new.perform(conversation.id)

      expect(conversation.reload.state).to eq("active")
      expect(conversation.pending_turns).to be_empty
      texts = conversation.messages.flat_map { |m| Array(m.content) }
                          .filter_map { |b| b["text"] if b["type"] == "text" }
      expect(texts.index("The taqueria it is.")).to be < texts.index("actually, never mind")
    end

    # Two taps, or two tabs: both pass the controller while the question
    # is open. The first settles it; the second would reach the loop with
    # the conversation active and raise, failing the job and stranding
    # whatever was queued behind it. It is dropped instead.
    it "drops a second answer to a question the first already settled" do
      fingerprint = conversation.reload.pending_questions["fingerprint"]
      2.times do
        conversation.enqueue_turn!("kind" => "answer", "option_id" => "taqueria",
                                   "fingerprint" => fingerprint, "mode" => "manual")
      end
      allow(AnthropicClient).to receive(:new).and_return(StreamingScriptedClient.new(said("Done.")))

      expect { Chat::CompletionJob.new.perform(conversation.id) }.not_to raise_error

      expect(conversation.reload.state).to eq("active")
      expect(conversation.pending_turns).to be_empty
      expect(conversation.messages.flat_map { |m| Array(m.content) }.count { |b| b["type"] == "tool_result" }).to eq(1)
    end

    # Nothing is coming until the person answers, so a stream or the
    # sidebar's "working" mark must not wait on the held message.
    it "does not count the held message as something still running" do
      conversation.enqueue_turn!("kind" => "message", "text" => "actually, never mind")

      expect(conversation.reload.pending_turns?).to be(true)
      expect(conversation.runnable_turns?).to be(false)
    end
  end

  describe "answering" do
    before { run_with(turn(ask), text: "what can I eat at ninis") }

    def fingerprint = conversation.reload.pending_questions["fingerprint"]

    it "hands the model the option that was picked, not the words typed" do
      _, client = run_with(said("The taqueria has 12 dishes for you."),
                           answer: { "option_id" => "taqueria" }, fingerprint: fingerprint)

      expect(answered_text(client)).to include("taqueria")
      expect(answered_text(client)).to include("Nini's Taqueria")
      expect(conversation.reload.state).to eq("active")
      expect(conversation.pending_questions).to be_nil
    end

    # The escape hatch. An option list that misses the obvious answer is
    # worse than no options, so a person can always say something else —
    # and it is marked as their words rather than dressed up as a choice.
    it "takes an answer that was not on the list, and says so" do
      _, client = run_with(said("Got it."),
                           answer: { "text" => "neither, the one on Main" }, fingerprint: fingerprint)

      expect(answered_text(client)).to include("\"answered\": \"text\"")
      expect(answered_text(client)).to include("the one on Main")
    end

    # An id the server never wrote is the one thing this must not pass
    # through — accepting it as free text would put the model back to
    # interpreting a string, which is what the tool exists to remove.
    it "refuses an option id that is not on the list" do
      result, = run_with(said("unreachable"),
                         answer: { "option_id" => "invented" }, fingerprint: fingerprint)

      expect(result).not_to be_ok
      expect(conversation.reload.state).to eq("awaiting_answers")
    end

    # Fails closed, like the confirmation gate: a tab left open on an
    # earlier question must not answer whatever is parked now.
    it "refuses an answer bound to a different question" do
      result, = run_with(said("unreachable"),
                         answer: { "option_id" => "taqueria" }, fingerprint: "stale")

      expect(result).not_to be_ok
      expect(result.error).to match(/out of date/)
      expect(conversation.reload.state).to eq("awaiting_answers")
    end

    it "refuses a missing fingerprint rather than treating it as a pass" do
      result, = run_with(said("unreachable"), answer: { "option_id" => "taqueria" })

      expect(result).not_to be_ok
      expect(conversation.reload.state).to eq("awaiting_answers")
    end
  end
end
