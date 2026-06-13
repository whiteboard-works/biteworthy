# frozen_string_literal: true

module Ingestion
  # Assigns cuisine / prep / diet / allergen tags to menu items. Request
  # shape + item rendering are inherited from ResolvePrompt; this is just
  # the instructions.
  class ResolveTagsPrompt < ResolvePrompt
    SYSTEM_INSTRUCTIONS = <<~MD.strip
      You assign cuisine / preparation / diet / allergen tags to menu
      items. The tag catalog is below — it's the only source of truth
      for slugs.

      For each item I send, return:
        * `resolved`: best-matching tag slugs from the catalog, each
          with a confidence (0..1). Tag liberally on cuisine + prep
          + flavor families; be careful with allergen.contains_*
          tags — only emit one when the description literally names
          an allergen ingredient.
        * `unresolved`: literal phrases that look like tags but aren't
          in the catalog (e.g., "house-smoked"), for human curation.

      Rules:
        * Use slugs **verbatim** — no fuzzy matches.
        * `index` in the response must equal the input index.
        * Order preserved.
        * Output JSON only.
    MD
  end
end
