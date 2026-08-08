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

        title_from(text)
        enqueue("kind" => "message", "text" => text, "page" => page_context)
      end

      def confirm
        return render_error("Nothing is waiting on you.", :conflict) unless conversation.awaiting_confirmation?

        approved = confirm_answer
        return render_error("Send confirm: true or false.") if approved.nil?

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
        conversation.enqueue_turn!(payload)
        Chat::CompletionJob.perform_later(conversation.id)
        render json: { queued: true, after: cursor }, status: :accepted
      end

      def relay
        position  = resume_from
        deadline  = Time.current + STREAM_SECONDS
        last_beat = Time.current

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

      # The list needs a label and the first thing the user said is the
      # best one available without spending a model call on it.
      def title_from(text)
        return if conversation.title.present?

        conversation.update!(title: text.truncate(60, separator: " "))
      end
    end
  end
end
