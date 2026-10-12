# frozen_string_literal: true

module Ingestion
  # The text of a fetched menu page, for the model. Raw HTML is mostly
  # scripts, styles, and markup: salsaleedos.net/menus is 2.2 MB for about
  # 10 KB of menu, and sending it whole failed with "prompt is too long:
  # 1068223 tokens". schema.org Menu JSON-LD is kept, since some
  # restaurant sites put the whole menu there.
  module HtmlText
    module_function

    DROPPED = "script, style, noscript, svg, template, iframe, link, meta"
    LINE_BREAKS = "br, p, div, li, tr, h1, h2, h3, h4, h5, h6, section, article, ul, ol, dl, table"
    # Inline and cell elements often touch their neighbours with no
    # whitespace ("<td>Hummus</td><td>8</td>", "Hummus<span>$8</span>");
    # a space on both sides keeps the name and the price apart.
    SPACED = "td, th, dt, dd, span, a, option, label, b, strong, em, i"
    MENU_JSON_LD = %r{"@type"\s*:\s*(?:\[[^\]]*?)?"(?:https?://schema\.org/)?Menu|"hasMenu}

    def declared_charset(doc)
      meta = doc.at_css("meta[charset]")&.[]("charset")
      meta ||= doc.css("meta[http-equiv]")
                  .find { |m| m["http-equiv"].to_s.casecmp?("content-type") }
                  &.[]("content").to_s[/charset\s*=\s*["']?([\w-]+)/i, 1]
      meta&.strip&.downcase.presence
    end

    def html?(content_type, body)
      content_type.to_s.include?("html") ||
        (content_type.to_s == "application/xml" && body.to_s[0, 512].lstrip.downcase.start_with?("<!doctype html", "<html"))
    end

    def call(html)
      # Blobs come back as binary with no charset. A page whose <meta>
      # declares a non-UTF-8 charset is re-read in that charset; everything
      # else is UTF-8 with stray bytes scrubbed, since Nokogiri's Latin-1
      # default turns "jalapeño" into mojibake the matcher cannot resolve.
      # The declaration is read from parsed elements, so a commented-out
      # or quoted <meta> does not count.
      doc = Nokogiri::HTML(html.to_s.dup.force_encoding(Encoding::UTF_8).scrub(""), nil, "UTF-8")
      declared = declared_charset(doc)
      if declared && !declared.match?(/\Autf-?8\z/)
        # Nokogiri resolves labels and aliases ("latin1"); one it cannot
        # read keeps the UTF-8 parse.
        doc = begin
          Nokogiri::HTML(html.to_s.b, nil, declared)
        rescue ArgumentError, EncodingError
          doc
        end
      end
      json_ld = doc.css('script[type="application/ld+json"]').map { |s| s.text.strip }
                   .select { |s| s.match?(MENU_JSON_LD) }
      doc.css(DROPPED).remove
      doc.css(LINE_BREAKS).each { |n| n.add_next_sibling("\n") }
      doc.css(SPACED).each do |n|
        n.add_previous_sibling(" ")
        n.add_next_sibling(" ")
      end
      visible = doc.text.gsub(/[ \t\r\f\v ]+/, " ").gsub(/ *\n\s*/, "\n").strip
      [ visible, *json_ld ].join("\n\n").strip
    end
  end
end
