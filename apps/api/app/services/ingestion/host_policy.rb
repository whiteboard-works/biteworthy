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
  # Toast ordering HTML.
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
    end
  end
end
