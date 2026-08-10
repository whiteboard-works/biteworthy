# frozen_string_literal: true

module Chat
  # Runs a turn off the request cycle.
  #
  # A turn is about a minute of model calls and tool runs. Held inside an
  # `ActionController::Live` action it occupied a Puma thread for the whole
  # time and — worse — died with the request: a proxy timeout, a deploy, or
  # a closed laptop killed the turn itself, not just the view of it. Here
  # the HTTP request only writes down what was asked and hands off; the
  # turn finishes regardless of who is still watching.
  #
  # Drains the whole queue before giving up the conversation, so rapid-fire
  # messages serialize behind the lock instead of racing, and none are
  # dropped.
  class CompletionJob < ApplicationJob
    queue_as :default

    def perform(conversation_id)
      conversation = Conversation.find_by(id: conversation_id)
      return if conversation.nil?

      loop do
        # Someone else holds the lock. They re-check the queue after they
        # release, so this turn is theirs to run — and re-enqueuing here
        # would spin.
        run = ConversationRun.acquire(conversation)
        return if run.nil?

        turn = conversation.next_pending_turn!
        if turn.nil?
          run.release!(outcome: "nothing_queued")
          return
        end

        execute(conversation, run, turn)

        # The run was released by the loop's ensure before this check, so a
        # turn enqueued while we were busy is picked up here rather than
        # stranded — that ordering is what closes the release race.
        break unless conversation.pending_turns?
      end
    end

    private

    def execute(conversation, run, turn)
      writer = EventWriter.new(run)
      AgentLoop.new(
        conversation,
        public_host: ENV["PUBLIC_HOST"].presence,
        on_event:    writer,
        run:         run,
        page:        turn["page"],
        mode:        turn["mode"]
      ).run(**arguments_for(turn))
    ensure
      # The terminal event is the client's cue to stop reading, so it has
      # to be on the table even if the turn blew up on its way out.
      writer&.flush!
    end

    def arguments_for(turn)
      case turn["kind"]
      when "confirm" then { confirm: turn["confirm"], fingerprint: turn["fingerprint"] }
      else                { text: turn["text"] }
      end
    end
  end
end
