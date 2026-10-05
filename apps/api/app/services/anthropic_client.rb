# frozen_string_literal: true

require "base64"

# Thin Faraday wrapper around Anthropic's `/v1/messages` endpoint.
# This is the foundation for the Phase 2 ingestion pipeline — the
# vision-extraction and ingredient/tag-resolution jobs (Phase 2.3 +
# 2.4) all hit this client.
#
# Design choices worth knowing:
#
# * **Prompt caching** is the difference between a $0.001 menu and a
#   $0.05 menu. Every system block we build can carry
#   `cache_control: { type: "ephemeral" }`; Anthropic caches the prefix
#   of system content for 5 minutes. The `system_blocks` helper makes it
#   one keyword arg.
#
# * **Vision input** accepts anything that responds to `download` (the
#   ActiveStorage::Blob shape) or to `read` (raw IO). The bytes are
#   base64-encoded and shipped as `{type: "image", source: {...}}`. We
#   never write the image to disk in this layer.
#
# * **Structured output** is enforced after the response by validating
#   against a JSON Schema (see `ResponseParser`). Anthropic doesn't have
#   a native "JSON mode" the way OpenAI does, so we lean on the system
#   prompt instructing the model to return strict JSON and then
#   validate. Failures raise `AnthropicClient::ValidationError` so the
#   ingestion job can transition the run to `:failed` cleanly.
#
# * **Retries**: faraday-retry on 429 + 5xx with exponential backoff,
#   3 attempts. Auth errors (401 / 403) are not retried — they're
#   raised as `ApiError` immediately.
#
# Usage:
#
#     client = AnthropicClient.new
#     response = client.messages_create(
#       system: client.system_blocks(
#         { text: "You are an OCR for restaurant menus...",
#           cache: true }
#       ),
#       messages: [
#         { role: "user", content: [
#           client.image_block(blob),
#           { type: "text", text: "Extract every menu item." }
#         ] }
#       ],
#       response_schema: MenuExtractionSchema
#     )
class AnthropicClient
  ENDPOINT          = "https://api.anthropic.com"
  MESSAGES_PATH     = "/v1/messages"
  ANTHROPIC_VERSION = "2023-06-01"
  DEFAULT_MODEL     = "claude-sonnet-4-6"
  DEFAULT_MAX_TOKENS = 8_000

  # Raised whenever the upstream API returns a non-2xx status. The
  # `status` and `body` fields let callers decide whether to surface
  # the error to the user or retry on the next tick.
  class ApiError < StandardError
    attr_reader :status, :body, :response_headers

    def initialize(status:, body:, response_headers: {}, message: nil)
      @status           = status
      @body             = body
      @response_headers = response_headers
      super(message || "Anthropic API returned #{status}: #{body.is_a?(String) ? body[0, 200] : body.inspect}")
    end
  end

  # Raised when the response body parses as JSON but doesn't satisfy
  # the schema we sent up. Carries the raw body + the validator's
  # error list so the ingestion job can include them in failure_message.
  class ValidationError < StandardError
    attr_reader :raw_body, :errors

    def initialize(raw_body:, errors:)
      @raw_body = raw_body
      @errors   = errors
      super("Anthropic response failed JSON Schema validation: #{errors.join('; ')}")
    end
  end

  # The model ran out of output budget mid-sentence.
  #
  # Its own class because it is not a validation failure, and calling it
  # one sent us looking in the wrong place for months: a `max_tokens`
  # response is well-formed JSON that simply stops, so `JSON.parse` blows
  # up with "unexpected end of input" and the run was recorded as
  # `schema_validation_failed` — a message that says the model wrote
  # something wrong when in fact it wrote something *unfinished*, and the
  # fix is a bigger budget or a smaller ask rather than a better prompt.
  class TruncatedError < StandardError
    attr_reader :raw_body, :max_tokens

    def initialize(raw_body:, max_tokens:)
      @raw_body   = raw_body
      @max_tokens = max_tokens
      super("Anthropic stopped at the #{max_tokens}-token output limit; the response is incomplete")
    end
  end

  attr_reader :api_key, :model, :base_url

  # The `usage` object from the most recent successful messages_create
  # call ({"input_tokens" =>, "output_tokens" =>,
  # "cache_read_input_tokens" =>, "cache_creation_input_tokens" =>}).
  # Phase 6.1.1 — jobs read this after each call to accrue real cost
  # onto IngestionRun.api_cost_cents. Nil until a call succeeds.
  attr_reader :last_usage

  # `timeout` and `retries` exist for callers whose work is optional.
  # The defaults are sized for the vision call that legitimately runs
  # minutes, and a caller on a user's critical path inherits that budget
  # whether or not its own request deserves it — a 240-second read plus
  # three retries is the right patience for extracting a menu and the
  # wrong patience for anything a person is waiting behind.
  def initialize(api_key: nil, model: nil, base_url: nil, conn: nil, timeout: nil, retries: nil)
    @api_key  = api_key  || ENV["ANTHROPIC_API_KEY"] || ""
    @model    = model    || DEFAULT_MODEL
    @base_url = base_url || ENDPOINT
    @conn     = conn # tests can inject a stubbed Faraday connection
    @timeout  = timeout
    @retries  = retries
  end

  # Low-level pass-through to /v1/messages. Returns a parsed Hash on
  # success; raises ApiError (with status + body) on non-2xx and
  # ValidationError if response_schema is supplied and the response
  # text doesn't match.
  def messages_create(system:, messages:, max_tokens: DEFAULT_MAX_TOKENS, response_schema: nil, model: nil, **extra)
    body = {
      model:      model || @model,
      max_tokens: max_tokens,
      system:     system,
      messages:   messages
    }.merge(extra)

    response = connection.post(MESSAGES_PATH, body.to_json)

    unless (200..299).cover?(response.status)
      raise ApiError.new(
        status: response.status,
        body: response.body,
        response_headers: response.headers
      )
    end

    parsed = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
    @last_usage = parsed["usage"]

    # Checked for **every** non-streaming caller, not only the ones that
    # asked for a schema. A schema-less caller gets a silently
    # half-finished answer otherwise, which is the quieter version of the
    # same bug. Raised before parsing because a truncated response *is* a
    # parse failure, so whichever check runs first names the error — and
    # "the model wrote malformed JSON" is the wrong name for "the model
    # was cut off", pointing at the prompt when the problem is the budget.
    if parsed["stop_reason"] == "max_tokens"
      raise TruncatedError.new(raw_body: ResponseParser.first_text(parsed), max_tokens: max_tokens)
    end

    return parsed if response_schema.nil?

    ResponseParser.parse_and_validate(ResponseParser.first_text(parsed), response_schema)
  end

  # Streaming twin of `messages_create`. Returns the same assembled Hash,
  # and yields `(:text | :thinking, fragment)` as the model writes so a
  # caller can put words on screen instead of a spinner.
  #
  # **Not retried.** The retry middleware replays the whole request, and
  # by the time a mid-stream failure happens the caller has already shown
  # the user half an answer — a silent second attempt would duplicate it.
  # A failure here surfaces to the caller, which for the chat means one
  # honest error rather than two conflicting replies.
  def messages_stream(system:, messages:, max_tokens: DEFAULT_MAX_TOKENS, model: nil, **extra, &on_delta)
    stream = Stream.new(&on_delta)
    body   = { model: model || @model, max_tokens: max_tokens, system: system, messages: messages, stream: true }
             .merge(extra)
    failure = +""

    response = stream_connection.post(MESSAGES_PATH) do |req|
      req.body = body.to_json
      # on_data fires for error responses too, and those bodies are plain
      # JSON rather than SSE — buffer them so the raise below can report
      # what upstream actually said.
      req.options.on_data = proc do |chunk, _overall, env|
        (200..299).cover?(env&.status.to_i) ? stream << chunk : failure << chunk
      end
    end

    unless (200..299).cover?(response.status)
      raise ApiError.new(status: response.status, body: failure.presence || response.body,
                         response_headers: response.headers)
    end

    @last_usage = stream.usage
    message = stream.message

    # Logged, not raised — unlike the non-streaming path.
    #
    # The caller has already put this answer on someone's screen word by
    # word. Turning a visible, mostly-complete reply into an error would
    # replace something useful with nothing; the honest handling is that
    # the operator can find out it happened. The chat is the only
    # streaming caller and its `MAX_TOKENS` covers thinking *and* text on
    # Opus 5, so a long think followed by a clipped answer is the shape
    # to watch for.
    if message.is_a?(Hash) && message["stop_reason"] == "max_tokens"
      Rails.logger.warn(
        "[anthropic] streamed response hit the #{max_tokens}-token output limit; answer is incomplete"
      )
    end

    message
  end

  # Build a `system` array of content blocks. Each input is a Hash like
  # `{text: "...", cache: true}`; cache: true means add the
  # `cache_control: {type: "ephemeral"}` block-level attribute.
  #
  # Anthropic counts cache breakpoints, not blocks — only mark the
  # final block of the cacheable prefix to maximize the cached span.
  def system_blocks(*blocks)
    blocks.flatten.map do |b|
      block = { type: "text", text: b.fetch(:text) }
      block[:cache_control] = { type: "ephemeral" } if b[:cache]
      block
    end
  end

  # Build an image content block from an ActiveStorage::Blob (responds
  # to #download + #content_type) OR from a raw IO/String.
  def image_block(source, media_type: nil)
    if source.respond_to?(:download)
      data       = source.download
      media_type ||= source.content_type
    elsif source.respond_to?(:read)
      data = source.read
    else
      data = source.to_s
    end

    {
      type: "image",
      source: {
        type:       "base64",
        media_type: media_type || "image/jpeg",
        data:       Base64.strict_encode64(data)
      }
    }
  end

  # Build a document content block (Claude reads PDFs natively) from an
  # ActiveStorage::Blob or a raw IO/String. Menu PDFs go through here —
  # Anthropic's vision `image` block only accepts jpeg/png/gif/webp, so a
  # PDF sent as an image 400s.
  def document_block(source, media_type: nil)
    if source.respond_to?(:download)
      data       = source.download
      media_type ||= source.content_type
    elsif source.respond_to?(:read)
      data = source.read
    else
      data = source.to_s
    end

    {
      type: "document",
      source: {
        type:       "base64",
        media_type: media_type || "application/pdf",
        data:       Base64.strict_encode64(data)
      }
    }
  end

  private

  def connection
    @conn ||= Faraday.new(url: @base_url) do |f|
      # Read timeout is generous: the non-streaming vision call with an
      # 8k max_tokens budget legitimately runs minutes. faraday-retry
      # can multiply the worst case ~3x.
      f.options.open_timeout = Integer(ENV.fetch("ANTHROPIC_OPEN_TIMEOUT", 10))
      f.options.timeout      = @timeout || Integer(ENV.fetch("ANTHROPIC_READ_TIMEOUT", 240))
      f.request  :retry, max: @retries || 3,
                          interval: 0.5,
                          backoff_factor: 2,
                          retry_statuses: [429, 500, 502, 503, 504],
                          methods: %i[post]
      f.response :json, content_type: /\bjson$/
      f.headers["x-api-key"]         = @api_key
      f.headers["anthropic-version"] = ANTHROPIC_VERSION
      f.headers["content-type"]      = "application/json"
      f.adapter Faraday.default_adapter
    end
  end

  # No retry middleware (see messages_stream) and no JSON response
  # middleware — the body is an SSE stream that `Stream` parses itself.
  # Deliberately NOT `@conn ||` — that would hand a stream the retrying,
  # JSON-parsing connection built for `messages_create`, which is the exact
  # opposite of what `messages_stream` documents ("Not retried") and would
  # also point the JSON middleware at an SSE body. Latent while no instance
  # calls both, which is precisely how it would have survived to the first
  # one that did.
  def stream_connection
    @stream_connection ||= Faraday.new(url: @base_url) do |f|
      f.options.open_timeout = Integer(ENV.fetch("ANTHROPIC_OPEN_TIMEOUT", 10))
      f.options.timeout      = Integer(ENV.fetch("ANTHROPIC_READ_TIMEOUT", 240))
      f.headers["x-api-key"]         = @api_key
      f.headers["anthropic-version"] = ANTHROPIC_VERSION
      f.headers["content-type"]      = "application/json"
      f.headers["accept"]            = "text/event-stream"
      f.adapter Faraday.default_adapter
    end
  end
end
