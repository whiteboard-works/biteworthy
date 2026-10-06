# frozen_string_literal: true

module Ingestion
  # Maps (source, numeric_confidence) from resolver output to the
  # (source, confidence) written onto ItemIngredient / ItemTag join rows.
  #
  # Locked rules:
  # - Community accepts never produce "confirmed"
  # - Admin accept with a menu-text source (match/human/owner/nil) gives
  #   confirmed for any numeric, and a nil numeric doesn't crash
  # - Source "derived" (name or keyword inference) gives suggested
  # - Source "ai" gives suggested at >= 0.8, and inferred below 0.8 or nil
  # - Source "ingredient_derived" takes the parent ingredient's mapped
  #   confidence (via from_source) and keeps source ingredient_derived
  # - A dish takes its weakest ingredient's confidence; inference never
  #   raises it
  # - A dish with zero ingredient rows is suggested
  # - Unknown sources fail closed to inferred
  module ConfidenceMapper
    TRUSTED_SOURCES = %w[match human owner].freeze
    KNOWN_SOURCES = %w[match human owner derived ai ingredient_derived].freeze

    def self.accept_cap_for(decided_by)
      decided_by.nil? || decided_by.is_admin? ? "confirmed" : "suggested"
    end

    # 766's table-driven contract. accept_cap is "confirmed" (admin) or
    # "suggested" (community). from_source is the parent ingredient source
    # when mapping an allergen tag stamped ingredient_derived.
    def self.map_confidence(numeric, source, accept_cap, from_source: nil)
      source = source.to_s
      source = "match" if source.blank?

      if source == "ingredient_derived"
        parent = from_source.presence || "unknown"
        return map_confidence(numeric, parent, accept_cap)
      end

      return "inferred" unless KNOWN_SOURCES.include?(source)
      return "suggested" if source == "derived"

      if source == "ai"
        n = numeric.nil? ? 0.0 : numeric.to_f
        return n >= 0.8 ? "suggested" : "inferred"
      end

      accept_cap == "confirmed" ? "confirmed" : "suggested"
    end

    def self.map_row(payload_row, decided_by:)
      accept_cap = accept_cap_for(decided_by)
      source = payload_row.source.to_s
      source = "match" if source.blank?
      from_source = payload_row.respond_to?(:from_source) ? payload_row.from_source : nil

      unless KNOWN_SOURCES.include?(source)
        return { source: "derived", confidence: "inferred" }
      end

      {
        source: join_source_for(source),
        confidence: map_confidence(
          payload_row.confidence, source, accept_cap, from_source: from_source
        )
      }
    end

    def self.join_source_for(source)
      case source
      when "match", "human", "" then "human"
      when "owner" then "owner"
      when "derived" then "derived"
      when "ai" then "ai"
      when "ingredient_derived" then "ingredient_derived"
      else "derived"
      end
    end

    # Dish confidence from INGREDIENT rows only (not tags).
    # Zero ingredients → suggested. Otherwise → weakest ingredient.
    def self.dish_confidence_from_ingredients(ingredient_rows)
      return "suggested" if ingredient_rows.empty?

      confidences = ingredient_rows.map { |r| r[:confidence] }
      return "inferred" if confidences.include?("inferred")
      return "suggested" if confidences.include?("suggested")

      "confirmed"
    end
  end
end
