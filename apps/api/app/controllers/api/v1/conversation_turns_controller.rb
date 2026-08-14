module Api
  module V1
    # The thin entry point, and the relay that narrates what the job is
    # doing.
    #
    # Turns used to run here, inside the request. That held a Puma thread
    # for the length of a model conversation, and — worse — the turn died
    # with the request: a proxy timeout, a deploy, or a closed laptop
    # killed the work itself, not just the view of it. Now `create` and
    # `confirm` write down what was asked and hand off to
    # `Chat::CompletionJob`; `stream` reads the narration back out.
    #
    # **The stream is a view, not the record** — and now that is true of
    # the narration too. Events are rows, so a client that reconnects sends
    # the last position it saw and resumes from there, instead of waiting
    # blind for the turn to finish and refetching.
    class ConversationTurnsController < BaseController
      include ActionController::Live

      MAX_MESSAGE_CHARS = 20_000
      # How long one connection lasts before we close it and hand the
      # client a cursor to resume from. A thread is held for the length of
      # a turn, not the length of a session — the client opens a stream
      # only while a turn is in flight — so this bounds how long a single
      # thread can be held by one reader, not how long a turn may run.
      STREAM_SECONDS    = 300
      POLL_SECONDS      = 0.2
      # How often an idle stream asks whether its turn is still alive.
      # Bounds how long a reader that is already caught up stays connected,
      # without paying that query on every poll.
      IDLE_CHECK_SECONDS = 1.0
      # A silent minute reads as a hang to every proxy in the path.
      KEEPALIVE_SECONDS = 15
      # One turn's narration is tens of rows, not thousands.
      BATCH             = 200

      def create
        text = params[:message].to_s.strip
        return render_error("Type something first.") if text.blank?
        return render_error("That message is too long.") if text.length > MAX_MESSAGE_CHARS
        # Queuing a message behind a parked call would leave the tool_use
        # dangling while the model answered something else.
        if conversation.awaiting_confirmation?
          return render_error("Answer the pending confirmation first.", :conflict)
        end
        return render_error("Unknown mode.") unless apply_mode

        enqueue("kind" => "message", "text" => text, "page" => page_context)
      end

      def confirm
        return render_error("Nothing is waiting on you.", :conflict) unless conversation.awaiting_confirmation?

        approved = confirm_answer
        return render_error("Send confirm: true or false.") if approved.nil?
        return render_error("Unknown mode.") unless apply_mode

        enqueue("kind" => "confirm", "confirm" => approved, "fingerprint" => params[:fingerprint].presence)
      end

      # `Last-Event-ID` is the standard reconnect header and EventSource
      # sends it on its own; `?after=` is here for clients that roll their
      # own reader, which ours does because it needs POST semantics.
      def stream
        open_stream
        relay
      rescue StandardError => e
        Rails.logger.error("[chat] stream on #{conversation.id} failed: #{e.class}: #{e.message}")
        write_event({ type: "error", message: "Lost the connection to that turn. Reload to catch up." })
      ensure
        response.stream.close
      end

      private

      # The request's whole job: record what was asked, then tell a worker.
      # Recording first matters — a job that starts against an empty queue
      # has nothing to run.
      def enqueue(payload)
        cursor = last_position
        # Stamped now, not read by the job later. A mode picked while this
        # turn is in flight belongs to the next one — see `AgentLoop#initialize`.
        conversation.enqueue_turn!(payload.merge("mode" => conversation.chat_mode))
        Chat::CompletionJob.perform_later(conversation.id)
        render json: { queued: true, after: cursor }, status: :accepted
      end

      # A client may switch modes and send in one request, so the picker
      # cannot lose a race with the message it was changed for.
      #
      # An unrecognised value is refused rather than quietly read as
      # `manual`. Falling back is safe in one direction only: someone who
      # asked for `auto` and silently got `manual` is asked a question
      # they did not expect, but someone who asked for `planning` and
      # silently got `manual` has writes running they thought were off.
      def apply_mode
        mode = params[:mode].presence
        return true if mode.nil?
        return false unless Chat::ModePolicy::MODES.include?(mode.to_s)

        conversation.update!(chat_mode: mode.to_s)
        true
      end

      def relay
        position   = resume_from
        deadline   = Time.current + STREAM_SECONDS
        last_beat  = Time.current
        next_check = Time.current

        while Time.current < deadline && !@disconnected
          events = conversation.events.after(position).in_order.limit(BATCH).to_a
          events.each do |event|
            write_event(event.payload, id: event.position)
            position = event.position
          end

          # A terminal event ends the turn. Stay open only if something is
          # still queued behind it, so a finished conversation does not
          # hold a connection for five minutes.
          return if events.any? { |e| terminal?(e) } && !more_coming?

          if events.empty?
            # The same exit, for a reader that arrives after the turn is
            # already over — the common case being a reconnect at the last
            # position it saw. Its terminal event was consumed by an
            # earlier connection, so the check above can never fire, and
            # without this the loop polls an idle conversation until the
            # deadline: a thread held for five minutes to send nothing.
            #
            # Throttled because this branch runs every POLL_SECONDS while
            # a turn is thinking, and the check costs two queries.
            if Time.current >= next_check
              next_check = Time.current + IDLE_CHECK_SECONDS
              return if finished?(position)
            end

            if Time.current - last_beat >= KEEPALIVE_SECONDS
              write_comment("keepalive")
              last_beat = Time.current
            end
            sleep POLL_SECONDS
          else
            last_beat = Time.current
          end
        end

        # Fell out on the deadline with the turn still going. A menu scan
        # legitimately outlives one connection, and without this the client
        # cannot tell "the turn ended" from "your connection did" — it
        # would stop watching and redraw a half-finished turn as final.
        # Handing back the cursor makes the next connection a resume.
        write_event({ type: "reconnect", after: position }) if !@disconnected && more_coming?
      end

      def terminal?(event)
        %w[done error awaiting_confirmation].include?(event.payload["type"])
      end

      def more_coming?
        conversation.reload.pending_turns? ||
          ConversationRun.running.exists?(conversation_id: conversation.id)
      end

      # Nothing running or queued, and the reader has seen everything.
      #
      # The order is load-bearing. A turn that ended between the batch
      # read and this call has already written its terminal event, so the
      # queue is checked first and the events afterwards — the reverse
      # order can see an empty tail, then a drained queue, and close on a
      # `done` the client never received.
      def finished?(position)
        !more_coming? && !conversation.events.after(position).exists?
      end

      def resume_from
        cursor = request.headers["Last-Event-ID"].presence || params[:after].presence
        return cursor.to_i if cursor

        # No cursor means "from here on" — replaying the whole history
        # would redraw turns the client already has on screen.
        last_position
      end

      def last_position
        conversation.events.maximum(:position).to_i
      end

      # Deliberately not a loose boolean cast: those read anything that
      # isn't literally false as `true`, which would turn a malformed
      # request into approval for a destructive call.
      # Where the user was standing when they asked. Rides with the turn
      # rather than being read at run time, because by then they may have
      # navigated away.
      def page_context
        raw = params[:context]
        return nil if raw.blank?

        { "path" => raw[:path].to_s.first(200).presence,
          "restaurant" => raw[:restaurant].to_s.first(100).presence }.compact.presence
      end

      def confirm_answer
        case params[:confirm]
        when true, "true"   then true
        when false, "false" then false
        end
      end

      def conversation
        @conversation ||= current_user.conversations.find(params[:id])
      end

      def render_error(message, status = :unprocessable_entity)
        render json: { error: message }, status: status
      end

      def open_stream
        response.headers["Content-Type"]      = "text/event-stream"
        response.headers["Cache-Control"]     = "no-cache, no-store"
        # Nginx and friends buffer proxied responses by default, which
        # would hold every event until the turn ended.
        response.headers["X-Accel-Buffering"] = "no"
        # Rack::ETag buffers the whole body to digest it unless the
        # response already carries a validator.
        response.headers["Last-Modified"]     = Time.current.httpdate
      end

      # Writes never raise past here. A reader going away is normal now —
      # the turn is running in a job that does not care whether anyone is
      # watching.
      def write_event(payload, id: nil)
        return if @disconnected

        response.stream.write("id: #{id}\n") if id
        response.stream.write("data: #{payload.to_json}\n\n")
      rescue IOError, ActionController::Live::ClientDisconnected
        @disconnected = true
      end

      def write_comment(text)
        return if @disconnected

        response.stream.write(": #{text}\n\n")
      rescue IOError, ActionController::Live::ClientDisconnected
        @disconnected = true
      end
    end
  end
end
