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
    DECLARED_CHARSET = /<meta[^>]+charset\s*=\s*["']?([\w-]+)/i
    MENU_JSON_LD = %r{"@type"\s*:\s*(?:\[[^\]]*?)?"(?:https?://schema\.org/)?Menu|"hasMenu}

    def html?(content_type, body)
      content_type.to_s.include?("html") ||
        (content_type.to_s == "application/xml" && body.to_s[0, 512].lstrip.downcase.start_with?("<!doctype html", "<html"))
    end

    def call(html)
      # Blobs come back as binary with no charset. A page that declares a
      # non-UTF-8 charset (<meta charset="windows-1252">) is handed to
      # Nokogiri raw so the declaration wins; everything else is read as
      # UTF-8 with stray bytes scrubbed, since Nokogiri's Latin-1 default
      # turns "jalapeño" into mojibake the matcher cannot resolve.
      declared = html.to_s.b[0, 4096][DECLARED_CHARSET, 1]&.downcase
      doc = if declared && !declared.match?(/\Autf-?8\z/)
        Nokogiri::HTML(html.to_s.b)
      else
        Nokogiri::HTML(html.to_s.dup.force_encoding(Encoding::UTF_8).scrub(""), nil, "UTF-8")
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
