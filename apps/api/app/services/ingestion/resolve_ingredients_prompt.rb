# frozen_string_literal: true

module Ingestion
  # Maps menu-item descriptions onto ingredient slugs. Request shape +
  # item rendering live in ResolvePrompt; this is just the instructions.
  class ResolveIngredientsPrompt < ResolvePrompt
    SYSTEM_INSTRUCTIONS = <<~MD.strip
      You map menu-item descriptions onto ingredient slugs from a
      curated catalog. The catalog is below — it's the only source of
      truth for slugs.

      For each item I send, return:
        * `resolved`: best-matching ingredient slugs from the catalog,
          each with a confidence (0..1). Be specific — prefer
          "dairy-cheese" over the parent "dairy" if the description
          says "cheese".
        * `unresolved`: literal strings from the description that you
          believe are ingredients but couldn't find in the catalog
          (e.g., "chimichurri sauce" — useful raw material for the
          curation queue).

      Rules:
        * Use slugs **verbatim** — no fuzzy matches, no inventing.
        * `index` in the response must equal the index I gave you.
        * Items in the response must appear in the same order as the input.
        * Output JSON only. No prose, no markdown fences.
    MD
  end
end
