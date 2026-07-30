# frozen_string_literal: true

module Ingestion
  # Shared text normalization for the deterministic resolve stage. Both
  # the ingredient matcher and the tag deriver need the same view of a
  # menu string: lowercase ASCII words, split into "segments" at
  # punctuation and connective words, so "Grilled steak, cilantro & lime"
  # becomes [["grilled", "steak"], ["cilantro"], ["lime"]].
  module MenuText
    SEGMENT_BREAK_WORDS = %w[and or with].freeze

    module_function

    # Lowercase, fold diacritics (jalapeño → jalapeno), treat "&" as
    # "and" and hyphens/slashes as spaces, then drop everything that
    # isn't a-z, 0-9, or space.
    def normalize(text)
      ActiveSupport::Inflector
        .transliterate(text.to_s.downcase)
        .gsub("&", " and ")
        .tr("-/", "  ")
        .gsub(/[^a-z0-9 ]/, " ")
        .squish
    end

    # Split one or more raw strings into segments: arrays of normalized
    # word tokens that belong together. Breaks at punctuation ONLY —
    # connective words stay in the token stream so catalog terms that
    # contain them ("half and half", "sweet and sour sauce") remain
    # matchable as one phrase. Callers that want connective-free chunks
    # (the matcher's leftover handling) apply split_on_break_words.
    def segments(*texts)
      texts
        .flat_map { |t| t.to_s.split(/[,;.:()\[\]+]/) }
        .map { |raw| normalize(raw).split(" ") }
        .reject(&:empty?)
    end

    def split_on_break_words(tokens)
      tokens
        .chunk { |t| SEGMENT_BREAK_WORDS.include?(t) }
        .reject { |is_break, _| is_break }
        .map { |_, chunk| chunk }
    end
  end
end
