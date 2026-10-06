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
  # LocalBusiness / Place) only. A single-string address (or a
  # PostalAddress with everything in streetAddress) is split
  # best-effort into street / city / region / postal, and the raw
  # string is kept. Free prose is not parsed into an address —
  # inventing a spot the site did not list is the failure this
  # exists to prevent. A homepage that only links to /locations
  # comes back with `location_pages` so the caller can fetch that
  # page next — once, not in a loop.
  class SiteDiscoverer
    MENU_HINT     = /menu|carta|food|\.pdf\b|dishes|dinner|lunch/i
    LOCATION_HINT = /location|locations|find.?us|\bhours\b|contact/i
    JS_LOCATION_HREF = /(?:window\.)?location(?:\.href)?\s*=\s*['"]([^'"]+)['"]/i
    # Best-effort US-style "street, city, ST ZIP" (optional country).
    ADDRESS_SPLIT = /
      \A
      (?:(?<street>.+?),\s+)?
      (?<city>[^,]+),\s+
      (?<region>[A-Za-z]{2})\s+
      (?<postal>\d{5}(?:-\d{4})?)
      (?:,\s*(?<country>.+))?
      \z
    /x
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

    def self.location_oriented?(url)
      path = URI.parse(url.to_s).path.to_s
      LOCATION_HINT.match?(path)
    rescue URI::InvalidURIError
      false
    end

    def self.same_page?(left, right)
      a = URI.parse(left.to_s)
      b = URI.parse(right.to_s)
      a.scheme == b.scheme &&
        a.host.to_s.downcase == b.host.to_s.downcase &&
        normalize_path(a.path) == normalize_path(b.path)
    rescue URI::InvalidURIError
      false
    end

    def self.normalize_path(path)
      trimmed = path.to_s.sub(%r{/+\z}, "")
      trimmed.empty? ? "/" : trimmed
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

      @html = @fetched.io.read
      doc = Nokogiri::HTML(@html)
      base = canonical_url(doc)
      menus = menu_candidates(doc, base)
      spots = location_candidates(doc)
      pages = location_pages(doc, base)
      if menus.empty? && spots.empty? && pages.empty?
        add_sitemap_candidates!(base, menus, pages)
      end
      pages = pages.reject { |page| self.class.same_page?(page[:url], base) }

      Result.new(
        url: base, host: host_of(base),
        menu_candidates: menus,
        location_candidates: spots,
        location_pages: pages
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
        raw:         address&.dig(:raw),
        phone:       phone,
        hours:       hours.presence
      }.compact
    end

    def address_from(value)
      case value
      when Array
        address_from(value.first)
      when Hash
        address_from_hash(value)
      when String
        text = value.strip
        return nil if text.blank?

        split_address_string(text).merge(raw: text)
      end
    end

    def address_from_hash(value)
      street  = present(value["streetAddress"])
      city    = present(value["addressLocality"])
      region  = present(value["addressRegion"])
      postal  = present(value["postalCode"])
      country = present_country(value["addressCountry"])
      parts   = {
        street: street, city: city, region: region,
        postal_code: postal, country: country
      }.compact

      if street && city.blank? && region.blank? && postal.blank?
        parts = split_address_string(street).merge(raw: street)
      elsif street
        parts[:raw] = street
      end
      parts.compact.presence
    end

    def split_address_string(text)
      match = ADDRESS_SPLIT.match(text.to_s.strip)
      return { street: text.to_s.strip } unless match

      {
        street:      match[:street].presence,
        city:        match[:city].presence,
        region:      match[:region]&.upcase,
        postal_code: match[:postal],
        country:     match[:country].presence
      }.compact
    end

    def present_country(value)
      case value
      when Hash then present(value["name"] || value["addressCountry"])
      else present(value)
      end
    end

    def hours_from(spec)
      return [] if spec.nil?

      # Array(hash) is [[k, v], …] — wrap a single JSON-LD object ourselves.
      list = spec.is_a?(Array) ? spec : [ spec ]
      list.flat_map { |row| hour_rows(row) }
          .uniq { |row| [ row[:day_of_week], row[:opens_at], row[:closes_at] ] }
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

    def each_same_origin_link(doc, base, &block)
      base_uri = URI.parse(base)
      seen = {}
      emit = lambda do |href, text, title|
        href = href.to_s.strip
        return if href.blank? || href.start_with?("#", "mailto:", "tel:", "javascript:")

        abs = URI.join(base, href)
        return unless same_origin?(base_uri, abs)
        return if seen[abs.to_s]

        seen[abs.to_s] = true
        block.call(abs, text.to_s.gsub(/\s+/, " ").strip, title.to_s.strip)
      rescue URI::InvalidURIError
        nil
      end

      doc.css("a[href]").each do |anchor|
        emit.call(anchor["href"], anchor.text, anchor["title"])
      end
      doc.css("[data-href]").each do |node|
        emit.call(node["data-href"], node.text, node["title"] || node["aria-label"])
      end
      doc.css("[data-url]").each do |node|
        emit.call(node["data-url"], node.text, node["title"] || node["aria-label"])
      end
      @html.to_s.scan(JS_LOCATION_HREF).flatten.each do |href|
        emit.call(href, "", "")
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

    # Cheap extra pass only when the HTML had nothing: same-origin
    # sitemap paths, and only if robots.txt for User-agent * allows.
    def add_sitemap_candidates!(base, menus, pages)
      origin = origin_of(base)
      return if origin.blank?

      robots = fetch_soft(URI.join(origin, "/robots.txt").to_s)
      parsed = robots.nil? ? { sitemaps: [], disallows: [] } : parse_robots(robots)
      sitemap_urls = parsed[:sitemaps].select do |url|
        same_origin?(URI.parse(origin), URI.parse(url))
      rescue URI::InvalidURIError
        false
      end
      default = URI.join(origin, "/sitemap.xml").to_s
      if sitemap_urls.empty? && !robots_disallows?(parsed[:disallows], "/sitemap.xml")
        sitemap_urls = [ default ]
      end

      sitemap_urls.first(2).each do |sitemap_url|
        xml = fetch_soft(sitemap_url)
        next if xml.blank?

        extract_sitemap_locs(xml, base).each do |abs|
          haystack = [ abs.path, File.basename(abs.path) ].join(" ")
          pdf = abs.path.downcase.end_with?(".pdf")
          if pdf || MENU_HINT.match?(haystack)
            menus << { url: abs.to_s, kind: pdf ? "pdf" : "page", label: abs.path }
          elsif LOCATION_HINT.match?(haystack)
            pages << { url: abs.to_s, label: abs.path }
          end
        end
      end

      menus.replace(uniq_by_url(menus).first(MAX_LINKS))
      pages.replace(uniq_by_url(pages).first(MAX_LINKS))
    end

    def extract_sitemap_locs(xml, base)
      doc = Nokogiri::XML(xml)
      loc_urls = doc.xpath("//*[local-name()='loc']").map { |node| node.text.to_s.strip }
      child_sitemaps, page_locs = loc_urls.partition { |url| url.downcase.end_with?(".xml") }

      child_sitemaps.first(2).each do |child|
        next unless same_origin?(URI.parse(base), URI.parse(child))

        nested = fetch_soft(child)
        next if nested.blank?

        page_locs.concat(
          Nokogiri::XML(nested).xpath("//*[local-name()='loc']").map { |node| node.text.to_s.strip }
        )
      end

      base_uri = URI.parse(base)
      page_locs.filter_map do |href|
        abs = URI.parse(href)
        next unless abs.is_a?(URI::HTTP) && same_origin?(base_uri, abs)

        abs
      rescue URI::InvalidURIError
        nil
      end
    end

    def parse_robots(text)
      sitemaps = []
      disallows = []
      applies = false
      text.to_s.each_line do |line|
        line = line.split("#", 2).first.to_s.strip
        next if line.blank?

        key, _, value = line.partition(":")
        key = key.strip.downcase
        value = value.strip
        case key
        when "user-agent"
          applies = (value == "*")
        when "disallow"
          disallows << value if applies
        when "sitemap"
          sitemaps << value if value.present?
        end
      end
      { sitemaps: sitemaps, disallows: disallows }
    end

    def robots_disallows?(disallows, path)
      disallows.any? { |rule| rule.present? && (rule == "/" || path.start_with?(rule)) }
    end

    def fetch_soft(url)
      UrlFetcher.fetch(url).io.read
    rescue UrlFetcher::FetchError
      nil
    end

    def origin_of(url)
      uri = URI.parse(url.to_s)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

      default_port = uri.scheme == "https" ? 443 : 80
      suffix = uri.port && uri.port != default_port ? ":#{uri.port}" : ""
      "#{uri.scheme}://#{uri.host}#{suffix}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
