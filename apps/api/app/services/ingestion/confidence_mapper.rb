# frozen_string_literal: true

module Ingestion
  # Maps (source, numeric_confidence) from resolver output to the (source, confidence) that
  # gets written into ItemIngredient / ItemTag join rows, following the locked confidence rules.
  #
  # Locked rules (must hold):
  # - Community accepts never produce "confirmed"
  # - Admin accept with a menu-text source (match/human/owner/nil) gives confirmed for any numeric,
  #   and a nil numeric doesn't crash
  # - Source "derived" (name or keyword inference, e.g. pizza implies wheat) gives suggested
  # - Source "ai" gives suggested at >= 0.8, and inferred below 0.8 or when nil
  # - A dish takes its weakest ingredient's confidence; inference never raises it
  # - A dish with zero ingredient rows is suggested
  #
  # Unknown sources fail closed: only match/human/owner/nil are trusted; anything else maps to inferred.
  module ConfidenceMapper
    TRUSTED_SOURCES = %w[match human owner].freeze
    INFERRED_SOURCES = %w[derived ai].freeze

    # Map one payload row's (source, numeric) to (source, confidence) for the join table.
    # decided_by determines the accept confidence ("confirmed" for admin, "suggested" for community).
    def self.map_row(payload_row, decided_by:)
      source = payload_row.source.to_s
      numeric = payload_row.confidence
      accept_confidence = decided_by.nil? || decided_by.is_admin? ? "confirmed" : "suggested"

      # Fail closed: unknown sources become inferred
      unless TRUSTED_SOURCES.include?(source) || INFERRED_SOURCES.include?(source) || source.blank?
        return { source: "derived", confidence: "inferred" }
      end

      # Menu-text sources (match/human/owner/nil) → accept confidence
      if TRUSTED_SOURCES.include?(source) || source.blank?
        return { source: source.presence || "match", confidence: accept_confidence }
      end

      # Derived (name/keyword inference) → suggested, always
      if source == "derived"
        return { source: "derived", confidence: "suggested" }
      end

      # AI → suggested at >= 0.8, inferred otherwise (including nil)
      if source == "ai"
        conf = (numeric.to_f >= 0.8) ? "suggested" : "inferred"
        return { source: "ai", confidence: conf }
      end

      # Fallback (should never reach here due to the fail-closed check above)
      { source: "derived", confidence: "inferred" }
    end

    # Compute the dish confidence from its ingredient rows (NOT tags).
    # Zero ingredients → suggested.
    # Otherwise → weakest ingredient confidence.
    def self.dish_confidence_from_ingredients(ingredient_rows)
      return "suggested" if ingredient_rows.empty?

      confidences = ingredient_rows.map { |r| r[:confidence] }
      return "inferred" if confidences.include?("inferred")
      return "suggested" if confidences.include?("suggested")

      "confirmed"
    end
  end
end
