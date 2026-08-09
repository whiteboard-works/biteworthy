# frozen_string_literal: true

module Ingestion
  # The {slug, confidence, source} row that `ingredients_payload` and
  # `tags_payload` are made of — written by the resolver, the gap-fill merge
  # and human edits, read by promotion, the diff and the verify tools.
  #
  # Two rules the six hand-rolled copies of this hash each had to remember:
  #
  #   * jsonb rows are stored with STRING keys. Every staged row already in
  #     the database has that shape, so `dump` keeps producing it.
  #   * the same shape also arrives symbol-keyed — straight off a tool
  #     argument, or out of the matcher/deriver — before it has ever
  #     round-tripped through jsonb, which is why every reader defended with
  #     `row["slug"] || row[:slug]`. `load` is indifferent so they don't
  #     have to be.
  AssociationPayload = Data.define(:slug, :confidence, :source) do
    def self.load(row)
      row = row.respond_to?(:with_indifferent_access) ? row.with_indifferent_access : {}
      new(slug: row[:slug], confidence: row[:confidence], source: row[:source])
    end

    def self.load_all(rows)
      Array(rows).map { |row| load(row) }
    end

    def self.dump(slug:, confidence: nil, source: nil)
      new(slug: slug, confidence: confidence, source: source).dump
    end

    def dump
      { "slug" => slug, "confidence" => confidence, "source" => source }
    end
  end
end
