# frozen_string_literal: true

require "json"
require "nokogiri"
require "uri"

module Ingestion
  # Deterministic extract of same-origin menu links and location
  # candidates from a restaurant-owned page. No LLM. The chat calls
  # this through `discover_restaurant_site` and must still ask the
  # user which locations and which menu URL to use — this never starts
  # a scan.
  #
  # Locations come from JSON-LD (Restaurant / FoodEstablishment /
  # LocalBusiness / Place) only. Free text is not parsed into an
  # address; inventing a spot the site did not list is the failure
  # this exists to prevent. A homepage that only links to /locations
  # comes back with `location_pages` so the caller can fetch that page
  # next.
  class SiteDiscoverer
    MENU_HINT     = /menu|carta|food|\.pdf\b|dishes|dinner|lunch/i
    LOCATION_HINT = /location|locations|find.?us|\bhours\b|contact/i
    PLACE_TYPES   = %w[Restaurant FoodEstablishment LocalBusiness Place].freeze
    DAY_NAMES     = {
      "sunday" => 0, "monday" => 1, "tuesday" => 2, "wednesday" => 3,
      "thursday" => 4, "friday" => 5, "saturday" => 6
    }.freeze
    MAX_LINKS = 20

    Result = Struct.new(
      :url, :host, :menu_candidates, :location_candidates, :location_pages,
      keyword_init: true
    )

    def self.call(url)
      HostPolicy.check!(url)
      fetched = UrlFetcher.fetch(url)
      new(url, fetched).discover
    end

    def initialize(url, fetched)
      @url     = url.to_s
      @fetched = fetched
    end

    def discover
      if pdf?
        return Result.new(
          url: @url, host: host_of(@url),
          menu_candidates: [ { url: @url, kind: "pdf", label: @fetched.filename } ],
          location_candidates: [], location_pages: []
        )
      end

      doc = Nokogiri::HTML(@fetched.io.read)
      base = canonical_url(doc)
      Result.new(
        url: base, host: host_of(base),
        menu_candidates: menu_candidates(doc, base),
        location_candidates: location_candidates(doc),
        location_pages: location_pages(doc, base)
      )
    end

    private

    def pdf?
      @fetched.content_type.to_s.include?("pdf")
    end

    def canonical_url(doc)
      href = doc.at_css('link[rel="canonical"]')&.[]("href").to_s.strip
      return URI.join(@url, href).to_s if href.present?

      @url
    rescue URI::InvalidURIError
      @url
    end

    def menu_candidates(doc, base)
      candidates = []
      if MENU_HINT.match?(URI.parse(base).path.to_s)
        candidates << { url: base, kind: "page", label: "this page" }
      end

      each_same_origin_link(doc, base) do |abs, text, title|
        haystack = [ text, title, abs.path, File.basename(abs.path) ].join(" ")
        pdf = abs.path.downcase.end_with?(".pdf")
        next unless pdf || MENU_HINT.match?(haystack)

        candidates << {
          url:   abs.to_s,
          kind:  pdf ? "pdf" : "page",
          label: text.presence || title.presence || abs.path
        }
      end

      uniq_by_url(candidates).first(MAX_LINKS)
    end

    def location_pages(doc, base)
      pages = []
      each_same_origin_link(doc, base) do |abs, text, title|
        haystack = [ text, title, abs.path ].join(" ")
        next unless LOCATION_HINT.match?(haystack)

        pages << { url: abs.to_s, label: text.presence || title.presence || abs.path }
      end
      uniq_by_url(pages).first(MAX_LINKS)
    end

    def location_candidates(doc)
      uniq_locations(doc.css('script[type="application/ld+json"]').flat_map { |script|
        locations_from_json_ld(script.text)
      })
    end

    def locations_from_json_ld(text)
      data = JSON.parse(text.to_s)
      nodes_from(data).filter_map { |node| location_from_ld(node) if place_type?(node) }
    rescue JSON::ParserError
      []
    end

    def nodes_from(data)
      case data
      when Array then data.flat_map { |item| nodes_from(item) }
      when Hash
        graph = data["@graph"]
        graph ? nodes_from(graph) + [ data ] : [ data ]
      else
        []
      end
    end

    def place_type?(node)
      return false unless node.is_a?(Hash)

      types = Array(node["@type"]).map { |type| type.to_s.split("/").last }
      types.intersect?(PLACE_TYPES)
    end

    def location_from_ld(node)
      address = address_from(node["address"])
      hours   = hours_from(node["openingHoursSpecification"])
      name    = node["name"].to_s.strip.presence
      phone   = (node["telephone"] || node["phone"]).to_s.strip.presence
      return nil if name.blank? && address.blank?

      {
        name:        name,
        street:      address&.dig(:street),
        city:        address&.dig(:city),
        region:      address&.dig(:region),
        postal_code: address&.dig(:postal_code),
        country:     address&.dig(:country),
        phone:       phone,
        hours:       hours.presence
      }.compact
    end

    def address_from(value)
      case value
      when Array
        address_from(value.first)
      when Hash
        {
          street:      present(value["streetAddress"]),
          city:        present(value["addressLocality"]),
          region:      present(value["addressRegion"]),
          postal_code: present(value["postalCode"]),
          country:     present(value["addressCountry"])
        }.compact.presence
      when String
        text = value.strip
        text.present? ? { street: text } : nil
      end
    end

    def hours_from(spec)
      rows = Array(spec).flat_map { |row| hour_rows(row) }
      rows.uniq { |row| [ row[:day_of_week], row[:opens_at], row[:closes_at] ] }
    end

    def hour_rows(row)
      return [] unless row.is_a?(Hash)

      days = Array(row["dayOfWeek"]).filter_map { |day| day_number(day) }
      opens  = time_of_day(row["opens"])
      closes = time_of_day(row["closes"])
      days.map { |day| { day_of_week: day, opens_at: opens, closes_at: closes }.compact }
    end

    def day_number(value)
      token = value.to_s.split("/").last.to_s.downcase
      DAY_NAMES[token]
    end

    def time_of_day(value)
      text = value.to_s.strip
      return nil if text.blank?

      match = text.match(/\A(\d{1,2}):(\d{2})(?::\d{2})?\z/)
      return nil unless match

      hour = match[1].to_i
      return nil if hour > 23

      format("%02d:%s", hour, match[2])
    end

    def each_same_origin_link(doc, base)
      base_uri = URI.parse(base)
      doc.css("a[href]").each do |anchor|
        href = anchor["href"].to_s.strip
        next if href.blank? || href.start_with?("#", "mailto:", "tel:", "javascript:")

        abs = URI.join(base, href)
        next unless same_origin?(base_uri, abs)

        yield abs, anchor.text.to_s.gsub(/\s+/, " ").strip, anchor["title"].to_s.strip
      rescue URI::InvalidURIError
        next
      end
    end

    def same_origin?(base, other)
      base.scheme == other.scheme &&
        base.host.to_s.downcase == other.host.to_s.downcase
    end

    def uniq_by_url(rows)
      rows.uniq { |row| row[:url] }
    end

    def uniq_locations(rows)
      rows.uniq { |row| [ row[:name], row[:street], row[:city], row[:postal_code] ] }
    end

    def host_of(url)
      URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end

    def present(value)
      value.to_s.strip.presence
    end
  end
end
