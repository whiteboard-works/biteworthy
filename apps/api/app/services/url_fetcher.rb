# frozen_string_literal: true

# Phase 2.8 — fetch a remote menu URL (HTML or PDF) and return
# enough info for the controller to attach as an ActiveStorage blob.
#
# Anthropic vision handles PDFs directly, so for PDF responses we
# pass the bytes through. For HTML pages, the bytes pass through too
# — Anthropic's vision API also accepts HTML when wrapped as a
# document, and Phase 2 isn't trying to do JS-rendered scraping.
#
# Hard limits:
#   * 10 MB max — protects the API server from accidentally fetching
#     a multi-hundred-meg PDF.
#   * Follows up to 3 redirects.
#   * 15-second timeout.
class UrlFetcher
  MAX_BYTES   = 10 * 1024 * 1024
  TIMEOUT_SEC = 15

  class FetchError < StandardError
    attr_reader :status, :reason
    def initialize(reason, status: nil)
      @reason = reason
      @status = status
      super("UrlFetcher: #{reason}#{status ? " (status #{status})" : ''}")
    end
  end

  Result = Struct.new(:io, :content_type, :filename, :byte_size, keyword_init: true)

  def self.fetch(url, conn: nil)
    new(conn: conn).fetch(url)
  end

  def initialize(conn: nil)
    @conn = conn || default_connection
  end

  def fetch(url)
    raise FetchError.new("invalid_url") unless url.to_s.match?(/\Ahttps?:\/\//)

    response = @conn.get(url)
    unless (200..299).cover?(response.status)
      raise FetchError.new("non_2xx", status: response.status)
    end

    body = response.body.to_s
    if body.bytesize > MAX_BYTES
      raise FetchError.new("response_too_large")
    end

    Result.new(
      io:           StringIO.new(body),
      content_type: detect_content_type(response, body),
      filename:     filename_for(url, response),
      byte_size:    body.bytesize
    )
  end

  private

  def default_connection
    Faraday.new do |f|
      f.request  :retry, max: 2,
                          interval: 0.5,
                          backoff_factor: 2,
                          retry_statuses: [429, 500, 502, 503, 504],
                          methods: %i[get]
      f.response :follow_redirects, limit: 3
      f.options.timeout = TIMEOUT_SEC
      f.options.open_timeout = TIMEOUT_SEC
      f.adapter Faraday.default_adapter
    end
  rescue NameError, LoadError
    # `follow_redirects` middleware is in faraday-follow_redirects (a
    # separate gem). If unavailable, fall back to a plain connection;
    # callers that need redirects can supply their own conn:.
    Faraday.new do |f|
      f.options.timeout = TIMEOUT_SEC
      f.options.open_timeout = TIMEOUT_SEC
      f.adapter Faraday.default_adapter
    end
  end

  def detect_content_type(response, body)
    header = response.headers["content-type"].to_s.split(";").first&.strip
    return header if header.present?

    # Sniff PDF magic bytes when the server didn't tell us.
    body.start_with?("%PDF") ? "application/pdf" : "text/html"
  end

  def filename_for(url, response)
    raw  = File.basename(URI.parse(url).path)
    name = raw.presence && raw != "/" ? raw : "menu"

    if response.headers["content-type"].to_s.include?("pdf") && !name.end_with?(".pdf")
      name = "#{name}.pdf"
    end
    name = "#{name}.html" unless name.include?(".")
    name
  end
end
