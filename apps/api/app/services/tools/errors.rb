# frozen_string_literal: true

module Tools
  # Failures the *model* should see and react to, as opposed to bugs.
  #
  # Tools::Base turns these into `isError` tool responses rather than
  # JSON-RPC protocol errors: an agent that reads "you must be signed in"
  # can ask the user to log in, whereas a protocol error just aborts the
  # turn with nothing actionable.
  module Errors
    class Error < StandardError
      def initialize(message, code: "error")
        @code = code
        super(message)
      end

      attr_reader :code
    end

    class Unauthorized < Error
      def initialize(message = "You must be signed in to do that.")
        super(message, code: "unauthorized")
      end
    end

    class Forbidden < Error
      def initialize(message = "You do not have permission to do that.")
        super(message, code: "forbidden")
      end
    end

    class NotFound < Error
      def initialize(message = "Not found.")
        super(message, code: "not_found")
      end
    end

    class InvalidArgument < Error
      def initialize(message)
        super(message, code: "invalid_argument")
      end
    end
  end
end
