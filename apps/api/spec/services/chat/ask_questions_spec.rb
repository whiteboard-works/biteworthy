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
      expect(conversation.messages.map(&:content).flatten.to_s).to include("at least two options")
    end

    it "refuses options that share an id" do
      same = [ { "id" => "a", "label" => "One" }, { "id" => "a", "label" => "Two" } ]
      result, = run_with(turn(ask(options: same)), said("let me try again"), text: "hi")

      expect(result.state).to eq(:done)
      expect(conversation.reload.state).to eq("active")
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
