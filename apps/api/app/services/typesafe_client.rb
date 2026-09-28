# frozen_string_literal: true

# Thin Faraday wrapper around TypeSafe's System One endpoint (Jev).
#
# Jev does not generate text: a request is a `state` plus a map of typed
# questions (`noul` = yes/no probability, `choice`, `score`), and the
# answers come back under the same keys. That makes it a candidate for
# the pipeline's narrow classification calls, never for extraction —
# it takes no images. API reference: https://docs.typesafe.ai/api.md
#
# Only `Ingestion::JevCuisineShadow` calls it today, and only to compare
# against Haiku; nothing it returns is written anywhere.
#
# Timeouts are short on purpose: Jev answers in 70–500ms, and the one
# caller is optional work inside a background job.
class TypesafeClient
  ENDPOINT = "https://api.typesafe.ai"
  PATH     = "/v1/systemone"
  DEFAULT_MODEL = "jev-latest"

  class ApiError < StandardError
    attr_reader :status, :body

    def initialize(status:, body:)
      @status = status
      @body   = body
      super("TypeSafe API error #{status}: #{body.to_s.truncate(300)}")
    end
  end

  attr_reader :model, :last_usage

  # The versioned model that answered (`jev-1.13.0`), which the
  # `jev-latest` alias hides. Nil until a call succeeds.
  attr_reader :last_model

  def self.configured? = ENV["JEV_API_KEY"].present?

  def initialize(api_key: nil, model: nil, conn: nil)
    @api_key = api_key || ENV["JEV_API_KEY"] || ""
    @model   = model || ENV.fetch("JEV_MODEL", DEFAULT_MODEL)
    @conn    = conn
  end

  # Returns the `answers` map ({ "key" => { "type" => "noul", "noul" => 0.93 } }).
  def system_one(state:, questions:)
    response = connection.post(PATH, { model: @model, state: state, questions: questions }.to_json)
    raise ApiError.new(status: response.status, body: response.body) unless (200..299).cover?(response.status)

    parsed = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
    @last_usage = parsed["usage"]
    @last_model = parsed["model"]
    parsed.fetch("answers")
  end

  private

  def connection
    @conn ||= Faraday.new(url: ENDPOINT) do |f|
      f.options.open_timeout = 3
      f.options.timeout      = 5
      # 529 is TypeSafe's "overloaded"; the docs ask for backoff on it and 429.
      f.request  :retry, max: 1, interval: 0.5, backoff_factor: 2,
                          retry_statuses: [ 429, 500, 502, 503, 504, 529 ],
                          methods: %i[post]
      f.response :json, content_type: /\bjson$/
      f.headers["Authorization"] = "Bearer #{@api_key}"
      f.headers["Content-Type"]  = "application/json"
      f.adapter Faraday.default_adapter
    end
  end
end
