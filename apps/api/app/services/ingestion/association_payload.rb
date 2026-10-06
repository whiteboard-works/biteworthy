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
  #
  # `from_source` is optional: allergen tags inferred from an ingredient
  # keep the parent ingredient's source so ConfidenceMapper can reuse that
  # ingredient's mapped confidence.
  AssociationPayload = Data.define(:slug, :confidence, :source, :from_source) do
    def initialize(slug: nil, confidence: nil, source: nil, from_source: nil)
      super
    end

    def self.load(row)
      row = row.respond_to?(:with_indifferent_access) ? row.with_indifferent_access : {}
      new(
        slug: row[:slug],
        confidence: row[:confidence],
        source: row[:source],
        from_source: row[:from_source]
      )
    end

    def self.load_all(rows)
      Array(rows).map { |row| load(row) }
    end

    def self.dump(slug:, confidence: nil, source: nil, from_source: nil)
      new(slug: slug, confidence: confidence, source: source, from_source: from_source).dump
    end

    def dump
      row = { "slug" => slug, "confidence" => confidence, "source" => source }
      row["from_source"] = from_source if from_source.present?
      row
    end
  end
end
