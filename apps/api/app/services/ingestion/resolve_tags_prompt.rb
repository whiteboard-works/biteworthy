# frozen_string_literal: true

module Ingestion
  class ResolveTagsPrompt
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

    def self.system(client, catalog_text)
      client.system_blocks(
        { text: SYSTEM_INSTRUCTIONS },
        { text: catalog_text, cache: true }
      )
    end

    def self.user_messages(items)
      Ingestion::ResolveIngredientsPrompt.user_messages(items)
    end
  end
end
