# frozen_string_literal: true

require "uri"

module Ingestion
  # ToS-safe fetch policy. UrlFetcher, start_menu_scan, and site
  # discovery all refuse these hosts *before* any HTTP request, so a
  # prompt telling the model "don't scrape DoorDash" cannot be the only
  # line of defence.
  #
  # Allowed seeds stay restaurant-owned sites, same-origin PDFs, user
  # paste, app uploads, and partner APIs. Forbidden as automated product
  # behaviour: DoorDash / order.online, Google Maps photo galleries, and
  # Toast ordering HTML — including a DoorDash/Toast white-label on a
  # custom domain (fingerprint after fetch: storefront cookies, headers,
  # or CDN asset hosts). A restaurant site that only *links* to DoorDash
  # stays allowed.
  class HostPolicy
    MESSAGE = "We cannot fetch menus from DoorDash, order.online, Google Maps, " \
              "or Toast ordering pages."

    NEXT_STEP = "Ask for the restaurant's own website URL, a same-origin menu " \
                "PDF, a photo or PDF upload through the app, or pasted menu " \
                "text. Do not fetch DoorDash, order.online, Google Maps, or " \
                "Toast ordering pages."

    # Registrable suffixes (and every subdomain). Matched as `host ==
    # suffix` or `host.end_with?(".#{suffix}")` so `notdoordash.com`
    # stays allowed.
    FORBIDDEN_HOST_SUFFIXES = %w[
      doordash.com
      order.online
      toasttab.com
      googleusercontent.com
    ].freeze

    # Script / stylesheet / iframe hosts that mean the page *is* a
    # DoorDash or Toast storefront, not a restaurant site that mentions
    # them. `cdn4dd.com` is DoorDash's CDN.
    STOREFRONT_ASSET_SUFFIXES = %w[
      doordash.com
      cdn4dd.com
      toasttab.com
      toastcdn.net
    ].freeze

    STOREFRONT_COOKIE = /\b(?:dd[_-][\w-]*|ddweb[_-]?[\w-]*|doordash[\w-]*|toast[_-][\w-]*)=/i
    STOREFRONT_HEADER = /\A(?:x-dd-|x-toast-)/i
    ASSET_TAG = /
      <(?:script|link|iframe)\b
      [^>]*?
      \b(?:src|href)\s*=\s*["']([^"']+)["']
    /ix

    class << self
      def forbidden?(url)
        uri = parse(url)
        return false unless uri

        host = normalize_host(uri.host)
        return false if host.blank?

        suffix_blocked?(host) || maps_url?(host, uri.path.to_s)
      end

      # Raises the same FetchError UrlFetcher uses for every other refusal,
      # so StartRun and DurangoSeed already know how to translate it.
      def check!(url)
        return unless forbidden?(url)

        raise UrlFetcher::FetchError.new("forbidden_host")
      end

      def refusal(url)
        uri = parse(url)
        {
          forbidden: true,
          host:      uri && normalize_host(uri.host),
          message:   MESSAGE,
          next_step: NEXT_STEP
        }
      end

      # Post-fetch fingerprint for a DoorDash/Toast white-label sitting
      # on a custom domain. UrlFetcher calls this on HTML 2xx so we
      # never parse the storefront. Outbound `<a href>` links are not
      # an asset tag and do not match.
      def storefront?(headers, body)
        storefront_headers?(headers) ||
          storefront_cookies?(headers) ||
          storefront_assets?(body)
      end

      private

      def parse(url)
        uri = URI.parse(url.to_s)
        uri.is_a?(URI::HTTP) ? uri : nil
      rescue URI::InvalidURIError
        nil
      end

      def normalize_host(host)
        host.to_s.downcase.delete_suffix(".")
      end

      def suffix_blocked?(host)
        FORBIDDEN_HOST_SUFFIXES.any? { |suffix| host == suffix || host.end_with?(".#{suffix}") }
      end

      # Maps hosts *and* google.*/maps paths. A restaurant site on a
      # Google Workspace custom domain is not this — those are not
      # `google.*`. `googleusercontent.com` is covered by the suffix list
      # (Maps gallery JPEGs).
      def maps_url?(host, path)
        return true if host == "maps.app.goo.gl"
        return true if host == "goo.gl" && path.start_with?("/maps")
        return true if host == "maps.google.com" || host.end_with?(".maps.google.com")
        return true if host.start_with?("maps.google.")
        google_host?(host) && path.start_with?("/maps")
      end

      def google_host?(host)
        host == "google.com" || host.end_with?(".google.com") ||
          host.match?(/\A(?:www\.)?google\.[a-z.]+(?:\.[a-z]{2})?\z/)
      end

      def storefront_headers?(headers)
        return false unless headers

        headers.each do |name, _|
          return true if name.to_s.match?(STOREFRONT_HEADER)
        end
        false
      end

      def storefront_cookies?(headers)
        return false unless headers

        values = Array(headers["set-cookie"]) + Array(headers["Set-Cookie"])
        STOREFRONT_COOKIE.match?(values.join("\n"))
      end

      def storefront_assets?(body)
        body.to_s.scan(ASSET_TAG).flatten.any? { |href| storefront_asset_host?(href) }
      end

      def storefront_asset_host?(href)
        host = normalize_host(URI.parse(href.to_s).host)
        return false if host.blank?

        STOREFRONT_ASSET_SUFFIXES.any? { |suffix| host == suffix || host.end_with?(".#{suffix}") }
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
