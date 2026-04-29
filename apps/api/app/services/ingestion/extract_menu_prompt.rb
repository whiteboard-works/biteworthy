# frozen_string_literal: true

# Builds the system + user message blocks for Phase 2.3's vision call.
#
# The system prompt is small + cacheable — once Anthropic caches it,
# every subsequent menu extraction in the 5-minute TTL window reads
# from cache (cheap input tokens). The user content carries the
# image(s) and a short instruction.
module Ingestion
  class ExtractMenuPrompt
    SYSTEM_INSTRUCTIONS = <<~MD.strip
      You are an OCR + structuring system for restaurant menus.

      You will be given one or more images of a menu (potentially
      multi-page). Extract every visible menu item and group them by
      section heading.

      Respond with **STRICT JSON ONLY** that matches this shape:

      {
        "sections": [
          {
            "name": "<section heading exactly as printed>",
            "items": [
              {
                "name": "<item name exactly as printed>",
                "description": "<the printed description, or null if absent>",
                "prices": [
                  {
                    "size": "<size label, or null when there is only one price>",
                    "price_cents": <integer cents, or null if absent>
                  }
                ]
              }
            ]
          }
        ]
      }

      Rules:
      * Do NOT invent items. If you can't read it, omit it.
      * Preserve item names verbatim — including spelling, capitalization,
        diacritics. Don't translate.
      * If a single item has multiple prices (small / large / etc.),
        emit one element per price in the `prices` array.
      * `price_cents` is in CENTS. "$4.50" becomes 450.
      * Output JSON only — no markdown fences, no commentary.
    MD

    USER_INSTRUCTIONS = "Extract every menu item from these images."

    # Build the system blocks array. Marks the instructions as
    # cached so a re-extraction within the 5-minute window pays
    # for cached input tokens instead of fresh ones.
    def self.system(client)
      client.system_blocks(text: SYSTEM_INSTRUCTIONS, cache: true)
    end

    # Build the user message: every input attachment is added as an
    # image block, then the short text instruction.
    def self.user_messages(client, blobs)
      content = blobs.map { |blob| client.image_block(blob) }
      content << { type: "text", text: USER_INSTRUCTIONS }
      [{ role: "user", content: content }]
    end
  end
end
