# frozen_string_literal: true

module Chat
  # What to tell someone when the *model's* API is the thing that failed.
  #
  # Every one of these used to read "The assistant is unavailable right
  # now. Try again in a moment." That sentence is true for an outage and
  # misleading for everything else, which is most of them: a conversation
  # that has outgrown the model's context window reads exactly the same
  # after a moment and after an hour, a rate limit clears on a schedule
  # the response header actually names, and a bad API key is not
  # something the reader can fix by waiting — it is ours. Someone who
  # retries four times and gets the same eleven words each time learns
  # only that the product is flaky.
  #
  # So the sentence names the failure and, more importantly, names the
  # move: wait this long, start a new chat, or stop trying because this
  # one is on us.
  #
  # The fallback is deliberate and it is the old sentence. A wrong
  # specific explanation is worse than a vague true one — telling someone
  # to start a new chat when the real problem was a five-second blip
  # costs them the conversation — so anything whose shape we do not
  # recognise stays generic rather than being forced into the nearest
  # bucket.
  module UpstreamError
    GENERIC = "The assistant is unavailable right now. Try again in a moment."

    DROPPED = "The connection to the assistant dropped before it finished answering. " \
              "Ask again — the conversation is intact and it can pick up from here."

    TIMED_OUT = "The assistant took too long to answer and the connection timed out. " \
                "Ask again — a long menu sometimes needs a second run, and asking for a " \
                "smaller piece of it is the reliable way through."

    OVERLOADED = "The assistant's API is overloaded right now, so this turn could not finish. " \
                 "That is upstream capacity, not anything about your chat — it usually clears " \
                 "within a minute or two."

    TOO_LONG = "This conversation has grown too long for the assistant to read in one go, so it " \
               "could not answer. Start a new chat — your profile and anything already saved are " \
               "unaffected."

    MISCONFIGURED = "The assistant is not configured correctly on our side, so it cannot answer " \
                    "at all. Trying again will not help — this one is ours to fix."

    REJECTED = "The assistant rejected this conversation, which is a bug on our side rather than " \
               "anything you did. Starting a new chat should get you moving again."

    # The sentence for `error`, or GENERIC when its shape is unfamiliar.
    #
    # The two Faraday errors are named individually rather than caught as
    # their common `Faraday::Error` parent, which also covers middleware
    # failures like `ParsingError` — those are our bug, not upstream
    # weather, and they belong in the crash path where someone will look
    # at them.
    def self.message_for(error)
      case error
      when AnthropicClient::Stream::IncompleteError then DROPPED
      when AnthropicClient::ApiError                then for_api_error(error)
      when Faraday::TimeoutError                    then TIMED_OUT
      when Faraday::ConnectionFailed                then GENERIC
      else GENERIC
      end
    end

    def self.for_api_error(error)
      body = detail(error.body)
      type = body["type"].to_s
      text = body["message"].to_s

      case error.status
      when 401, 403 then MISCONFIGURED
      when 429      then rate_limited(error)
      when 529      then OVERLOADED
      when 400      then context_window?(text) ? TOO_LONG : REJECTED
      else
        # A stream that carries its failure as an SSE `error` event
        # arrives here as status 200 — see `Stream#raise_stream_error` —
        # so the type is the only signal there is.
        return OVERLOADED if type == "overloaded_error"
        return TOO_LONG if type == "invalid_request_error" && context_window?(text)

        GENERIC
      end
    end
    private_class_method :for_api_error

    # "Try again in about 40 seconds" beats "in a moment" when upstream
    # has told us the actual number, and beats it most when the number is
    # much larger than a moment.
    def self.rate_limited(error)
      "The assistant hit its rate limit, so this turn could not finish. " \
        "Try again #{wait_hint(retry_after(error))}."
    end
    private_class_method :rate_limited

    def self.wait_hint(seconds)
      return "in a moment" if seconds.nil? || seconds <= 1
      return "in about #{seconds} seconds" if seconds < 60

      "in about #{(seconds / 60.0).ceil} minutes"
    end
    private_class_method :wait_hint

    def self.retry_after(error)
      value = header(error.response_headers, "retry-after")
      Integer(value.to_s.strip, exception: false)
    end
    private_class_method :retry_after

    # Faraday's own headers are case-insensitive; a plain Hash from a
    # test double or a re-serialized error is not.
    def self.header(headers, name)
      return nil unless headers.respond_to?(:find)

      headers.find { |key, _| key.to_s.casecmp?(name) }&.last
    end
    private_class_method :header

    # The one 400 worth its own sentence, because it is the one with a
    # different answer: the transcript no longer fits, and `Compaction`
    # has already done what it can.
    def self.context_window?(text)
      text.match?(/too long|context window|maximum.*tokens|exceeds?.*token/i)
    end
    private_class_method :context_window?

    # The error envelope, whichever of the three shapes it arrived in:
    # a parsed `{"type" => "error", "error" => {...}}` from the JSON
    # middleware, that same JSON still as a String (the streaming
    # connection has no JSON middleware), or the bare error object an SSE
    # `error` event carries.
    def self.detail(body)
      parsed = body.is_a?(String) ? safe_json(body) : body
      return {} unless parsed.is_a?(Hash)

      inner = parsed["error"]
      inner.is_a?(Hash) ? inner : parsed
    end
    private_class_method :detail

    def self.safe_json(text)
      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end
    private_class_method :safe_json
  end
end
