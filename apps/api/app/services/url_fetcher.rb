# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "uri"

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
#   * Follows up to 3 redirects, re-validating each hop against the
#     SSRF blocklist (cloud metadata + RFC1918 + loopback + …).
#   * 15-second timeout.
class UrlFetcher
  MAX_BYTES     = 10 * 1024 * 1024
  TIMEOUT_SEC   = 15
  MAX_REDIRECTS = 3

  # Reject fetches whose resolved address falls in any of these
  # ranges. Mitigates SSRF against cloud metadata (169.254.169.254),
  # internal services, and the local network. Re-checked on every
  # redirect hop. Best-effort only — DNS rebinding between this check
  # and the socket connect is still possible, but raises the bar
  # enough for menu URLs (user-supplied via /api/v1/ingestion_runs).
  BLOCKED_IPV4 = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),    # CGNAT
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),   # link-local + cloud metadata
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.0.0.0/24"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("198.18.0.0/15"),
    IPAddr.new("224.0.0.0/4"),      # multicast
    IPAddr.new("240.0.0.0/4"),      # reserved
  ].freeze

  BLOCKED_IPV6 = [
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),         # unique-local
    IPAddr.new("fe80::/10"),        # link-local
    IPAddr.new("ff00::/8"),         # multicast
  ].freeze

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
    current_url = url.to_s
    redirects   = 0

    loop do
      raise FetchError.new("invalid_url") unless current_url.match?(/\Ahttps?:\/\//)
      validate_safe_url!(current_url)

      response = @conn.get(current_url)

      if (300..399).cover?(response.status) && response.headers["location"].present?
        raise FetchError.new("too_many_redirects") if redirects >= MAX_REDIRECTS
        redirects += 1
        current_url = URI.join(current_url, response.headers["location"]).to_s
        next
      end

      unless (200..299).cover?(response.status)
        raise FetchError.new("non_2xx", status: response.status)
      end

      body = response.body.to_s
      raise FetchError.new("response_too_large") if body.bytesize > MAX_BYTES

      return Result.new(
        io:           StringIO.new(body),
        content_type: detect_content_type(response, body),
        filename:     filename_for(current_url, response),
        byte_size:    body.bytesize
      )
    end
  end

  private

  def validate_safe_url!(url)
    host = URI.parse(url).host
    raise FetchError.new("invalid_url") if host.nil? || host.empty?

    addresses = resolve_addresses(host)
    raise FetchError.new("dns_failed") if addresses.empty?

    addresses.each do |addr|
      ip      = IPAddr.new(addr)
      blocked = ip.ipv4? ? BLOCKED_IPV4 : BLOCKED_IPV6
      raise FetchError.new("blocked_address") if blocked.any? { |range| range.include?(ip) }
    end
  rescue URI::InvalidURIError, IPAddr::InvalidAddressError
    raise FetchError.new("invalid_url")
  end

  def resolve_addresses(host)
    # Literal IP — skip DNS.
    [IPAddr.new(host).to_s]
  rescue IPAddr::InvalidAddressError
    Resolv.getaddresses(host)
  end

  def default_connection
    # No follow_redirects middleware: redirects are handled in #fetch
    # so each hop re-runs validate_safe_url!.
    Faraday.new do |f|
      f.request :retry, max: 2,
                        interval: 0.5,
                        backoff_factor: 2,
                        retry_statuses: [429, 500, 502, 503, 504],
                        methods: %i[get]
      f.options.timeout      = TIMEOUT_SEC
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
