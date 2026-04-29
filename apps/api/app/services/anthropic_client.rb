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

  attr_reader :api_key, :model, :base_url

  def initialize(api_key: nil, model: nil, base_url: nil, conn: nil)
    @api_key  = api_key  || ENV["ANTHROPIC_API_KEY"] || ""
    @model    = model    || DEFAULT_MODEL
    @base_url = base_url || ENDPOINT
    @conn     = conn # tests can inject a stubbed Faraday connection
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
    return parsed if response_schema.nil?

    text = ResponseParser.first_text(parsed)
    ResponseParser.parse_and_validate(text, response_schema)
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

  private

  def connection
    @conn ||= Faraday.new(url: @base_url) do |f|
      f.request  :retry, max: 3,
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
end
