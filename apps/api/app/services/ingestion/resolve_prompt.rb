# frozen_string_literal: true

module Ingestion
  # Shared machinery for the two "resolve" prompts (ResolveIngredients,
  # ResolveTags). Both build the same request shape — instruction block
  # + cached catalog block as the system prompt, and one numbered
  # user-message listing the items to resolve. They differ only in the
  # instruction text, which each subclass supplies as SYSTEM_INSTRUCTIONS.
  class ResolvePrompt
    # Build the system blocks. The catalog is the LAST block, marked
    # cached — Anthropic caches the prefix up to and including the last
    # cache_control block, so we get the (large) catalog cached without
    # paying to cache the (smaller) instruction text. `self::` resolves
    # the calling subclass's SYSTEM_INSTRUCTIONS.
    def self.system(client, catalog_text)
      client.system_blocks(
        { text: self::SYSTEM_INSTRUCTIONS },
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

    # `items` is an array of `{name:, description:, section:}` hashes
    # (string or symbol keys). Renders a compact numbered list the model
    # can index back into.
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
