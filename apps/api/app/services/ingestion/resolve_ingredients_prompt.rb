# frozen_string_literal: true

module Ingestion
  class ResolveIngredientsPrompt
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

    # Build the system blocks. The catalog is the LAST block, marked
    # cached — Anthropic caches the prefix up to and including the
    # last cache_control block, so we get the catalog cached without
    # paying for caching the (smaller) instruction text.
    def self.system(client, catalog_text)
      client.system_blocks(
        { text: SYSTEM_INSTRUCTIONS },
        { text: catalog_text, cache: true }
      )
    end

    def self.user_messages(items)
      [{
        role: "user",
        content: [
          { type: "text",
            text: "Resolve ingredients for the following items:\n\n" + items_block(items) }
        ]
      }]
    end

    # `items` is an array of `{name:, description:, section:}` hashes.
    # Renders a compact numbered list the model can index.
    def self.items_block(items)
      items.each_with_index.map do |item, i|
        section     = item[:section] || item["section"]
        name        = item[:name] || item["name"]
        description = item[:description] || item["description"]

        line = "[#{i}] #{name}"
        line += " (section: #{section})" if section.present?
        line += "\n    description: #{description}" if description.present?
        line
      end.join("\n")
    end
  end
end
