# frozen_string_literal: true

module Ingestion
  # The one rule for name-level diet claims ("Gluten-Free Pizza",
  # "GF Penne"): a dish whose NAME claims a diet never receives, from
  # inference or from its own name, an ingredient that would contradict
  # the claim — deriving contains-gluten onto a Gluten-Free Pizza would
  # veto the claim itself (TagDeriver::Diet::CONTRADICTED_BY) and hide
  # the dish from exactly the users it exists for. Explicit DESCRIPTION
  # evidence is exempt: a dish that lists wheat flour is not gluten-free
  # whatever its name says.
  #
  # Both inference seams apply it: DeterministicResolver (the
  # implied-base union and the name-scan catalog matches) and
  # GapFillResolveJob's merge of model rows — the prompt literally asks
  # for "pizza implies crust", so without the same gate the model would
  # re-add what the resolver suppressed.
  module DietClaims
    module_function

    # Diet-claim slugs present in the given (name) segments.
    def claims_in(segments)
      TagDeriver.keyword_hits(segments, TagDeriver::Diet::KEYWORDS, confidence: 0)
                .map { |hit| hit[:slug] }
    end

    # Would attributing an ingredient at `slug`/`path` contradict one of
    # `claims`? Rides on TagDeriver::Allergen so the gluten subtrees and
    # cross-root oddballs (coconut → tree nut) stay defined in one place.
    def contradicted?(claims, slug:, path:)
      return false if claims.empty?

      allergens = TagDeriver::Allergen.call(
        resolved_ingredients: [ { slug: slug, path: path, confidence: 0, source: "derived" } ]
      ).map { |t| t[:slug] }
      claims.any? { |claim| Array(TagDeriver::Diet::CONTRADICTED_BY[claim]).intersect?(allergens) }
    end
  end
end
