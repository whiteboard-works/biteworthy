# frozen_string_literal: true

module Ingestion
  # Hard sodas matched while their aliases sat on the `alcohol` root.
  # The celiac presets avoid `alcohol.beer`, which does not expand up, so
  # an alcohol-root join shows those dishes as safe. Alias and join
  # backfills move the catalog; this remaps a leftover payload slug at
  # promote! so undo-then-re-accept cannot recreate the root join.
  module HardSoda
    module_function

    PHRASES = [ "hard ginger beer", "hard root beer", "spiked root beer" ].freeze
    FROM = "alcohol"
    TO = "alcohol-beer"
    CURATOR = %w[human owner].freeze

    def remap_payload(payload, name:, description:)
      rows = Array(payload).map { |row| stringify(row) }
      return rows unless phrase_in?("#{name} #{description}")

      has_beer = rows.any? { |row| row["slug"] == TO }
      name_has_phrase = phrase_in?(name)
      rows.filter_map do |row|
        next row unless row["slug"] == FROM
        next row if CURATOR.include?(row["source"].to_s) && !name_has_phrase
        next if has_beer

        has_beer = true
        row.merge("slug" => TO)
      end
    end

    def phrase_in?(text)
      hay = normalize(text)
      PHRASES.any? { |phrase| hay.include?(phrase) }
    end

    # Same folding as MenuText.normalize / the hard-soda data migrations.
    def normalize(text)
      ActiveSupport::Inflector
        .transliterate(text.to_s.downcase)
        .gsub("&", " and ")
        .tr("-/", "  ")
        .gsub(/[^a-z0-9 ]/, " ")
        .squish
    end

    def stringify(row)
      row.respond_to?(:to_h) ? row.to_h.stringify_keys : { "slug" => row }
    end
  end
end
