module Api
  module V1
    # Chat conversations: the list, one transcript, and the lifecycle.
    #
    # Turns themselves stream, so they live in ConversationTurnsController
    # — ActionController::Live changes the response object for every
    # action in a controller, which would break these plain JSON reads.
    class ConversationsController < BaseController
      MAX_LIMIT = 50
      # One turn's narration is tens of rows, not thousands.
      BATCH     = 200

      def index
        conversations = current_user.conversations
                                    .newest_first
                                    .limit(page_limit(default: 20, max: MAX_LIMIT))
                                    .offset(page_offset)
        render json: { conversations: conversations.map { |c| Chat::Serializer.conversation(c) } }
      end

      def create
        conversation = current_user.conversations.create!(title: params[:title].presence)
        render json: Chat::Serializer.conversation(conversation, messages: true), status: :created
      end

      # The reconnect path: a dropped stream loses nothing, because every
      # turn was persisted as it happened.
      def show
        # Usage detail is for whoever operates the tools, not for a diner —
        # it is spend and cache accounting, and it is the only part of this
        # payload that is not about the conversation itself.
        render json: Chat::Serializer.conversation(conversation, messages: true,
                                                                 usage: current_user.is_admin?)
      end

      def destroy
        conversation.destroy!
        head :no_content
      end

      # The narration as plain JSON, for clients that cannot hold an SSE
      # stream open.
      #
      # React Native's fetch is XHR-backed and does not expose a readable
      # response body, so the mobile app cannot consume `/stream` without
      # pulling in an EventSource polyfill. The events are rows either way
      # — the SSE relay is just a long-lived reader over this same table —
      # so handing them back as JSON costs nothing and makes the narration
      # consumable by any client at all.
      #
      # `after` is the same cursor the stream uses, so a client can switch
      # between the two without losing its place.
      def events
        rows = conversation.events.after(params[:after]).in_order.limit(BATCH)
        render json: {
          events: rows.map { |e| e.payload.merge("position" => e.position) },
          # Whether it is worth asking again. Saves a client polling a
          # finished conversation forever.
          running: running?
        }
      end

      # The stop button. Raises a flag the running turn reads at its next
      # lifecycle checkpoint; it does not kill anything itself.
      #
      # It has to be a different request from the turn it stops — the
      # streaming one is busy for the length of the turn, which is exactly
      # the window the user wants to interrupt.
      def stop
        run = ConversationRun.running.find_by(conversation_id: conversation.id)
        return render json: { error: "Nothing is running." }, status: :conflict if run.nil?

        run.update!(abort_requested_at: Time.current)
        head :accepted
      end

      private

      def running?
        conversation.pending_turns? ||
          ConversationRun.running.exists?(conversation_id: conversation.id)
      end

      def conversation
        @conversation ||= current_user.conversations.find(params[:id])
      end
    end
  end
end
