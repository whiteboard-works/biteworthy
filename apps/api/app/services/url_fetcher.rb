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
#   * 10 MB max. Enforced on Content-Length before the request when the
#     server declares one, and on the body afterwards when it does not —
#     an undeclared response is still fully buffered before it can be
#     rejected, so this bounds what we *use*, not always what we download.
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
    IPAddr.new("::/128"),           # unspecified — routes to localhost
    IPAddr.new("::1/128"),
    IPAddr.new("64:ff9b::/96"),     # NAT64 well-known prefix: embeds an
                                    # IPv4 address this check cannot see
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
      # ToS hosts are refused before DNS or the GET, including redirect hops.
      Ingestion::HostPolicy.check!(current_url)
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

      declared = response.headers["content-length"].to_s
      raise FetchError.new("response_too_large") if declared.present? && declared.to_i > MAX_BYTES

      body = response.body.to_s
      raise FetchError.new("response_too_large") if body.bytesize > MAX_BYTES

      content_type = detect_content_type(response, body)

      if html_content?(content_type) && Ingestion::HostPolicy.storefront?(response.headers, body)
        raise FetchError.new("forbidden_host")
      end

      # Detect bot challenges or interstitials AFTER content-type detection,
      # so we know whether the response is HTML when we expect something else.
      expected_type = expected_content_type_for(current_url)
      if expected_type && expected_type != content_type
        if bot_challenge?(body, content_type)
          raise FetchError.new("bot_challenge")
        else
          raise FetchError.new("unexpected_content_type")
        end
      end

      return Result.new(
        io:           StringIO.new(body),
        content_type: content_type,
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
      ip      = normalize(IPAddr.new(addr))
      blocked = ip.ipv4? ? BLOCKED_IPV4 : BLOCKED_IPV6
      raise FetchError.new("blocked_address") if blocked.any? { |range| range.include?(ip) }
    end
  rescue URI::InvalidURIError, IPAddr::InvalidAddressError
    raise FetchError.new("invalid_url")
  end

  # An IPv4-mapped IPv6 address is an IPv4 address wearing a hat:
  # `::ffff:169.254.169.254` reaches cloud metadata, `::ffff:127.0.0.1`
  # reaches loopback, `::ffff:10.0.0.1` reaches the internal network. Ruby
  # reports all three as `ipv4? == false`, so without this they were
  # checked against the IPv6 list — which has no mapped range — and sailed
  # straight through every guard below.
  def normalize(ip)
    ip.ipv4_mapped? ? ip.native : ip
  rescue StandardError
    ip
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

    # Sniff content when the header is missing, obviously wrong, or generic.
    # Servers sometimes return application/xml for HTML pages, generic
    # octet-stream for PDFs, or the wrong MIME type entirely.
    if header.blank? || looks_like_wrong_content_type?(header, body) || generic_content_type?(header)
      return sniff_content_type(body)
    end

    header
  end

  def generic_content_type?(header)
    %w[
      application/octet-stream
      binary/octet-stream
    ].include?(header)
  end

  def looks_like_wrong_content_type?(header, body)
    # application/xml but the body is actually HTML
    header == "application/xml" && body.strip.start_with?("<html", "<!DOCTYPE html", "<!doctype html")
  end

  def sniff_content_type(body)
    stripped = body.strip

    # PDF magic bytes
    return "application/pdf" if stripped.start_with?("%PDF")

    # HTML markers
    if stripped.start_with?("<html", "<!DOCTYPE html", "<!doctype html") ||
       stripped.match?(%r{<html[\s>]|<head[\s>]|<body[\s>]}i)
      return "text/html"
    end

    # XML markers (after ruling out HTML)
    return "application/xml" if stripped.start_with?("<?xml")

    # Default fallback: treat as HTML if we can't determine
    "text/html"
  end

  # Infer what content type a URL *should* return based on its extension.
  # Returns nil if we have no expectation (e.g., a generic /menu path).
  def html_content?(content_type)
    content_type.to_s.include?("html")
  end

  def expected_content_type_for(url)
    path = URI.parse(url).path.to_s.downcase
    return "application/pdf" if path.end_with?(".pdf")
    nil
  rescue URI::InvalidURIError
    nil
  end

  # Detect common bot challenges and captcha/WAF interstitials.
  # These are HTML pages returned instead of the actual resource,
  # typically very small and containing specific known patterns.
  def bot_challenge?(body, content_type)
    return false unless content_type == "text/html" || content_type == "application/xml"
    return false if body.bytesize > 5_000 # Challenges are typically tiny

    lower = body.downcase

    # Specific challenge markers that are definitive, not incidental mentions
    [
      "/.well-known/sgcaptcha",         # SiteGround captcha path
      "__cf_chl",                       # Cloudflare challenge parameter
      "cf-chl-bypass",                  # Cloudflare challenge bypass
      "challenge-platform",             # Cloudflare challenge platform
      "/_guard/",                       # DDoS-Guard
      "g-recaptcha",                    # Google reCAPTCHA widget
      "hcaptcha"                        # hCaptcha widget
    ].any? { |marker| lower.include?(marker) } ||
      # "Just a moment..." title with challenge script is Cloudflare's signature
      (lower.include?("just a moment") && lower.include?("challenge-platform")) ||
      # Akamai/Imperva block pages with specific markers
      (lower.include?("akamai") && lower.include?("reference")) ||
      (lower.include?("imperva") && lower.include?("incident"))
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
