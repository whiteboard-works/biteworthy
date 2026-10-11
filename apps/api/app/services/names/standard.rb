# frozen_string_literal: true

module Names
  # The BiteWorthy naming standard for dishes. Menus and PDFs print names
  # in capitals for emphasis and the extraction prompt preserves them
  # verbatim, so without this an all-caps menu stays all-caps on a phone.
  #
  # Only text that is mostly capitals is rewritten: a name becomes Title
  # Case, a description sentence case. Anything cased on purpose
  # ("McDonald's", "BBQ Pulled Pork") is left as written, and short
  # all-caps names ("BLT", "KFC") are assumed to be acronyms.
  module Standard
    SHOUTING_RATIO = 0.7
    MIN_LETTERS    = 4

    ACRONYMS = %w[BBQ BLT BLTA DF GF II III IPA IV KC MSG NY NYC PB&J USA USDA V VG VGN XL XXL].to_set.freeze
    SMALL_WORDS = %w[a al an and as at but by con de del di en for from in la le of on or the to via w with y].to_set.freeze

    # A leading or trailing "*" is a footnote marker (usually the
    # raw/undercooked advisory), not part of the name.
    EDGE_ASTERISKS = /\A[\s*]+|[\s*]+\z/

    module_function

    def item_name(name)
      return name if name.nil?

      stripped = name.gsub(EDGE_ASTERISKS, "").presence || name.strip
      shouting?(stripped) ? title_case(stripped) : stripped
    end

    def description(text)
      return text if text.nil? || !shouting?(text)

      sentence_case(text)
    end

    def shouting?(text)
      letters = text.scan(/\p{L}/)
      return false if letters.size < MIN_LETTERS

      letters.count { |l| l.match?(/\p{Lu}/) } >= letters.size * SHOUTING_RATIO
    end

    def title_case(text)
      first = true
      text.split(/(\s+)/).map do |token|
        next token if token.blank?

        word = title_word(token, first: first)
        first = false
        word
      end.join
    end

    # Hyphen and slash pieces are cased on their own: "BBQ-Style",
    # "Salt-and-Pepper", "w/Bacon".
    def title_word(token, first:)
      token.split(%r{([-/])}).each_with_index.map do |part, i|
        next part if part.match?(%r{\A[-/]\z})

        title_part(part, small_ok: !(first && i.zero?))
      end.join
    end

    def title_part(part, small_ok:)
      return part.upcase if acronym?(part)

      lower = part.downcase
      small_ok && SMALL_WORDS.include?(lower) ? lower : capitalize(lower)
    end

    def sentence_case(text)
      text.downcase
          .gsub(/(\A|[.!?]\s+)([^\p{L}\p{N}]*)(\p{L})/) { "#{$1}#{$2}#{$3.upcase}" }
          .gsub(/[\p{L}&]+/) { |word| acronym?(word) ? word.upcase : word }
    end

    def acronym?(token)
      ACRONYMS.include?(token.gsub(/[^\p{L}&]/, "").upcase)
    end

    # Upcases the first letter unless a digit comes first ("12oz").
    def capitalize(part)
      part.sub(/\A([^\p{L}\p{N}]*)(\p{L})/) { "#{$1}#{$2.upcase}" }
    end
  end
end
