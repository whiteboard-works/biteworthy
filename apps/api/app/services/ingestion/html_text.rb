# frozen_string_literal: true

module Ingestion
  # What a person reading a fetched menu page would see, for the model.
  # Raw HTML is mostly scripts, styles, and markup: salsaleedos.net/menus
  # is 2.2 MB for about 10 KB of menu, and sending it whole failed with
  # "prompt is too long: 1068223 tokens". schema.org JSON-LD is kept,
  # since some restaurant sites put the whole menu there.
  module HtmlText
    module_function

    DROPPED = "script, style, noscript, svg, template, iframe, link, meta"

    def html?(content_type, body)
      content_type.to_s.include?("html") ||
        (content_type.to_s == "application/xml" && body.to_s.lstrip.downcase.start_with?("<!doctype html", "<html"))
    end

    def call(html)
      doc = Nokogiri::HTML(html.to_s)
      # Only menu-bearing JSON-LD (schema.org Menu, MenuSection, MenuItem,
      # hasMenu); a Wix page's image and breadcrumb records would otherwise
      # pass the empty-page check and send the model nothing to read.
      json_ld = doc.css('script[type="application/ld+json"]').map { |s| s.text.strip }
                   .select { |s| s.match?(/"(?:@type"\s*:\s*"Menu\w*|hasMenu\w*)"/) }
      doc.css(DROPPED).remove
      doc.css("br, p, div, li, tr, h1, h2, h3, h4, h5, h6, section, article").each { |n| n.add_next_sibling("\n") }
      visible = doc.text.gsub(/[ \t\r\f\v ]+/, " ").gsub(/ *\n[\s]*/, "\n").strip
      [ visible, *json_ld ].join("\n\n").strip
    end
  end
end
