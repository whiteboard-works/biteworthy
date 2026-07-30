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
                ],
                "addons": [
                  {
                    "name": "<the thing being added>",
                    "price_cents": <integer cents, or null if absent>
                  }
                ],
                "image_bbox": { "x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0 }
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

      Add-ons / upsells:
      * A line offering to ADD something to a dish for extra money —
        "Add chicken $3", "+ guajillo salsa 4.00", "add avocado +$2" —
        is NOT a menu item. Emit it in the `addons` array of the item
        it modifies (the dish it is printed under or beside).
      * An addon's `name` is the thing being added, stripped of the
        "Add"/"+"/price scaffolding: "Add guajillo-tomatillo salsa +
        $4.00" becomes { "name": "guajillo-tomatillo salsa",
        "price_cents": 400 }.
      * A standalone dish that happens to be a side or extra ("Side of
        Guacamole" in a Sides section) is still a normal item — only
        lines that modify another dish become addons.
      * If an item has no add-on lines, OMIT the `addons` field.

      Per-dish photos:
      * Many menus include a small photo of an individual dish next to
        its name + description. When you see one, return its bounding
        box as `image_bbox: { "x": <left>, "y": <top>, "w": <width>,
        "h": <height> }`. All four are fractions in 0..1 of the source
        page: 0,0 = top-left corner, 1,1 = bottom-right corner.
      * If an item has NO inline photo on the page, OMIT the
        `image_bbox` field entirely. Don't return zero-sized or null
        boxes — absence means "no photo."
      * If a single page contains multiple images, prefer the one
        physically closest to the item's name + description.
    MD

    # NOTE: kept verbatim ("these images") on purpose — the ExtractMenuJob
    # live-cassette smoke matches the recorded request on body, so editing
    # this text (or SYSTEM_INSTRUCTIONS) invalidates the committed cassette
    # and needs a re-record with a real API key. The content-type routing
    # below is what makes PDF/text work; the wording is cosmetic. Generalize
    # it only alongside a cassette re-record.
    USER_INSTRUCTIONS = "Extract every menu item from these images."

    # Build the system blocks array. Marks the instructions as
    # cached so a re-extraction within the 5-minute window pays
    # for cached input tokens instead of fresh ones.
    def self.system(client)
      client.system_blocks(text: SYSTEM_INSTRUCTIONS, cache: true)
    end

    # Build the user message: each input attachment becomes the content
    # block Anthropic expects for its type, then the short instruction.
    def self.user_messages(client, blobs)
      content = blobs.map { |blob| content_block(client, blob) }
      content << { type: "text", text: USER_INSTRUCTIONS }
      [{ role: "user", content: content }]
    end

    # Route each input by content-type. Anthropic's vision `image` block
    # only accepts jpeg/png/gif/webp, so PDFs and text (URL scrapes come
    # back as text/html; pasted menus as text/plain) must NOT be sent as
    # images — doing so 400s with "media_type should be image/...".
    #   * PDF   → document block (Claude reads PDFs natively)
    #   * text/*→ text block (the model reads the menu text directly)
    #   * else  → image block (jpeg/png/gif/webp — and, unchanged,
    #             heic/heif, which still 400; converting them is a
    #             follow-up, but a text block of raw HEIC bytes would be
    #             worse, so they stay on the image path)
    def self.content_block(client, blob)
      ct = blob.content_type.to_s
      if ct == "application/pdf"
        client.document_block(blob)
      elsif ct.start_with?("text/")
        { type: "text", text: blob.download.to_s }
      else
        client.image_block(blob)
      end
    end
  end
end
