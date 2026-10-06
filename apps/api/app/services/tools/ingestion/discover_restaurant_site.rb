# frozen_string_literal: true

module Tools
  module Ingestion
    # Read a restaurant-owned homepage (or locations/menu page) and
    # return same-origin menu URLs plus location candidates. Does not
    # inherit Ingestion::Base — that pane is for scans, and this call
    # never creates one.
    class DiscoverRestaurantSite < Tools::Base
      audience :user

      tool_name "discover_restaurant_site"
      title "Discover menus and locations on a restaurant site"
      description <<~TEXT
        Fetch a restaurant's own website and list same-origin menu pages
        or PDFs plus location candidates found in structured data.

        Call this when a user pastes a homepage and wants to add the
        restaurant. Show them the locations and menu URLs and wait for
        them to pick. Do not start a scan, and do not invent a location
        the site did not list.

        If the page only links to a Locations or Contact page, call this
        once on that same-origin URL. If that page still has no
        addresses, ask the user for them — do not call this on the same
        page again. If nothing useful is found, ask for a menu page URL,
        a PDF, an upload, or pasted text.

        If menus clearly differ per location, scan each from its own
        source instead of cloning.

        DoorDash, order.online, Google Maps, and Toast ordering pages
        are refused — ask for the restaurant's own site, a PDF/photo
        upload, or pasted menu text.
      TEXT

      input_schema(
        properties: {
          url: {
            type: "string",
            description: "Restaurant-owned http(s) URL — homepage, locations page, or menu page/PDF."
          }
        },
        required: %w[url]
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { |args| "Looking at #{host_label(args[:url])}" }

      def self.perform(context:, url:)
        context.user!
        if ::Ingestion::HostPolicy.forbidden?(url)
          refusal = ::Ingestion::HostPolicy.refusal(url)
          return error(refusal[:message], code: "forbidden_host", next_step: refusal[:next_step], host: refusal[:host])
        end

        result = ::Ingestion::SiteDiscoverer.call(url)
        ok(
          url: result.url,
          host: result.host,
          menu_candidates: fence_rows(result.menu_candidates, :label),
          location_candidates: fence_locations(result.location_candidates),
          location_pages: fence_rows(result.location_pages, :label),
          next_step: next_step_for(result)
        )
      rescue UrlFetcher::FetchError => e
        fetch_failure(e)
      end

      def self.host_label(url)
        host = URI.parse(url.to_s).host
        host.present? ? host : "the restaurant site"
      rescue URI::InvalidURIError
        "the restaurant site"
      end
      private_class_method :host_label

      def self.fetch_failure(failure)
        if failure.reason == "forbidden_host"
          return error(
            ::Ingestion::HostPolicy::MESSAGE,
            code: "forbidden_host",
            next_step: ::Ingestion::HostPolicy::NEXT_STEP
          )
        end

        hint = case failure.reason
        when "bot_challenge"
          "The site blocked automated fetching. Ask the user to paste the menu, " \
          "upload a PDF or photos, or try a same-origin menu PDF."
        else
          "That URL could not be fetched. Ask for a same-origin menu PDF, " \
          "a photo/PDF upload, or pasted menu text."
        end
        error(hint, code: "url_fetch_failed", reason: failure.reason, next_step: hint)
      end
      private_class_method :fetch_failure

      ASK_ADDRESSES = "This page did not list addresses. Ask the user for the " \
                      "street address of each location (or paste them), then " \
                      "create_restaurant with those. Do not call " \
                      "discover_restaurant_site on this page again."

      ASK_MENU_SOURCE = "No menu or location URLs were found on this page. Ask " \
                        "the user for a same-origin menu page URL, a menu PDF, " \
                        "a photo or PDF upload, or pasted menu text."

      def self.next_step_for(result)
        if result.location_candidates.many?
          "Show the user these locations and ask which to import. Create one " \
          "restaurant per chosen spot (distinct names if the brand repeats), " \
          "scan the shared menu once, then clone_menu to siblings."
        elsif result.location_candidates.empty? && on_location_page?(result.url)
          ASK_ADDRESSES
        elsif result.location_candidates.empty? && other_location_pages(result).any?
          "This page did not list addresses. Call discover_restaurant_site on a " \
          "same-origin Locations or Contact URL, then ask which spots to add."
        elsif result.menu_candidates.any? || result.location_candidates.any?
          "Show the user the menu URLs (and any location). Create the restaurant " \
          "if we do not have it, then start_menu_scan on the menu URL they confirm."
        else
          ASK_MENU_SOURCE
        end
      end

      def self.on_location_page?(url)
        ::Ingestion::SiteDiscoverer.location_oriented?(url)
      end

      def self.other_location_pages(result)
        result.location_pages.reject { |page|
          ::Ingestion::SiteDiscoverer.same_page?(page[:url], result.url)
        }
      end
      private_class_method :next_step_for, :on_location_page?, :other_location_pages

      def self.fence_rows(rows, *keys)
        rows.map { |row| row.merge(keys.index_with { |key| untrusted(row[key]) }) }
      end
      private_class_method :fence_rows

      def self.fence_locations(rows)
        rows.map do |row|
          row.merge(
            name:   untrusted(row[:name]),
            street: untrusted(row[:street]),
            raw:    untrusted(row[:raw])
          ).compact
        end
      end
      private_class_method :fence_locations
    end
  end
end
