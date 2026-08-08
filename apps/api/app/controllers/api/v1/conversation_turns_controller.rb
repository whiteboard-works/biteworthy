module Api
  module V1
    # Runs one chat turn and narrates it over Server-Sent Events.
    #
    # A turn can take a minute — several model calls plus the tools in
    # between — so the alternative to streaming is a spinner with nothing
    # behind it. Events arrive as they happen: text and thinking as the
    # model writes, one pair per tool call, then a terminal event.
    #
    # **The stream is a view, not the record.** Every turn is persisted as
    # it runs, so a dropped connection costs nothing: the loop finishes
    # server-side and `GET /conversations/:id` replays it. That is what
    # makes a 60-second turn survive a proxy timeout or a closed laptop.
    class ConversationTurnsController < BaseController
      include ActionController::Live

      MAX_MESSAGE_CHARS = 20_000

      def create
        text = params[:message].to_s.strip
        return render_error("Type something first.") if text.blank?
        return render_error("That message is too long.") if text.length > MAX_MESSAGE_CHARS
        if conversation.awaiting_confirmation?
          return render_error("Answer the pending confirmation first.", :conflict)
        end

        title_from(text)
        stream_turn { |agent| agent.run(text: text) }
      end

      def confirm
        return render_error("Nothing is waiting on you.", :conflict) unless conversation.awaiting_confirmation?

        approved = confirm_answer
        return render_error("Send confirm: true or false.") if approved.nil?

        stream_turn { |agent| agent.run(confirm: approved, fingerprint: params[:fingerprint].presence) }
      end

      private

      # Deliberately not a loose boolean cast: those read anything that
      # isn't literally false as `true`, which would turn a malformed
      # request into approval for a destructive call.
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

      def stream_turn
        open_stream
        yield Chat::AgentLoop.new(conversation, public_host: public_host, on_event: method(:write_event))
      rescue StandardError => e
        # The loop already converts upstream and tool failures into error
        # events; reaching here means a bug. The user gets one honest
        # sentence rather than a hung stream.
        Rails.logger.error("[chat] turn on #{conversation.id} failed: #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
        write_event(type: "error", message: "Something went wrong on our end. Your conversation is saved.")
      ensure
        response.stream.close
      end

      def open_stream
        response.headers["Content-Type"]     = "text/event-stream"
        response.headers["Cache-Control"]    = "no-cache, no-store"
        # Nginx and friends buffer proxied responses by default, which
        # would hold every event until the turn ended.
        response.headers["X-Accel-Buffering"] = "no"
        # Rack::ETag buffers the whole body to digest it unless the
        # response already carries a validator.
        response.headers["Last-Modified"]    = Time.current.httpdate
        write_event(type: "open", conversation_id: conversation.id)
      end

      # Writes never raise past here: when the client is gone the turn
      # still has to finish, because finishing is what persists it.
      def write_event(payload)
        return if @disconnected

        response.stream.write("data: #{payload.to_json}\n\n")
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
