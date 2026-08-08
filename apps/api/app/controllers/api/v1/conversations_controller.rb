module Api
  module V1
    # Chat conversations: the list, one transcript, and the lifecycle.
    #
    # Turns themselves stream, so they live in ConversationTurnsController
    # — ActionController::Live changes the response object for every
    # action in a controller, which would break these plain JSON reads.
    class ConversationsController < BaseController
      MAX_LIMIT = 50

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
        render json: Chat::Serializer.conversation(conversation, messages: true)
      end

      def destroy
        conversation.destroy!
        head :no_content
      end

      private

      def conversation
        @conversation ||= current_user.conversations.find(params[:id])
      end
    end
  end
end
