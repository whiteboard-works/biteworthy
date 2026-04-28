# AI ingestion pipeline

The cold-start unlock. A contributor opens the app, points the camera at
a menu, and within a minute the items are staged in our database with
ingredient and tag suggestions. Five minutes of swipe-verify and the
restaurant is live.

The 2020 product needed a small army of Durango volunteers hand-typing
menus. v2 reduces that to "tap accept." The AI does the typing; humans
do the verifying.

## Inputs

| Input | Source |
|---|---|
| Photo | Mobile camera, multi-page capture |
| URL | Restaurant menu page on the web |
| PDF | Upload from web or mobile |

All three end up as ActiveStorage blobs attached to an `IngestionRun`.

## Stages

Each stage is a Solid Queue job; each is idempotent and resumable.
States: `queued → extracting → resolving → staged → published` (or
`failed` at any point).

### 1. Extract

Vision-capable Claude reads the input directly (no OCR step). The system
prompt is **prompt-cached** — it carries the full ingredient and tag
taxonomy as a structured table, which is the bulk of the tokens. After
the first call, every subsequent extraction reads the cache for cents.

Output (validated against a JSON Schema):

```json
{
  "sections": [
    {
      "name": "Tacos",
      "items": [
        {
          "name": "Carne Asada Taco",
          "description": "Grilled steak, cilantro, onion, lime.",
          "prices": [{ "size": null, "price_cents": 450 }]
        }
      ]
    }
  ]
}
```

### 2. Resolve

For each extracted item:

- **Name match.** `pg_trgm` similarity against existing items in the
  same restaurant > 0.85 → same dish. Avoids duplicates on re-ingestion.
- **Ingredient extract.** Second LLM call with the *full ingredient
  catalog* in context (cached). Output: `[{ slug, confidence }]`.
  Unknown strings → `unresolved_ingredients[]` for human curation.
- **Tag suggestion.** "contains-dairy", "vegan", "fried", etc., with
  confidence numbers.

### 3. Stage

Write to `ingestion_items`:

```ruby
IngestionItem.create!(
  ingestion_run: run,
  name: "Carne Asada Taco",
  description: "Grilled steak, cilantro, onion, lime.",
  ingredients_payload: [
    { slug: "meat-beef", confidence: 0.97 },
    { slug: "vegetable.onion", confidence: 0.93 },
  ],
  tags_payload: [
    { slug: "cuisine.mexican", confidence: 0.99 },
    { slug: "prep.grilled",    confidence: 0.95 },
  ],
)
```

### 4. Verify

Contributor opens a swipe UI:

- ✅ Accept → `IngestionItem.decision = 'accepted'`, promote to a real
  `Item` with `confidence = 'confirmed'`.
- ✏️ Edit → tweak ingredients / tags → `decision = 'edited'`, then
  promote.
- ❌ Reject → `decision = 'rejected'`, stays in the run for audit.

### 5. Publish

When the run hits ≥80% accepted (configurable per city/restaurant), the
restaurant flips to `status = 'published'` and shows up in search.

## Honest disclosure

This is the rule that keeps us safe for allergy users:

- Items promoted from AI extraction stay at `confidence: suggested`
  until a human confirms each ingredient/tag association.
- Strict-mode users (`user_profiles.strictness = 'strict'`) only see
  items where `items.confidence = 'confirmed'`.
- Hidden items always show **why**: "Hidden — contains dairy (cheese)" or
  "Hidden — strict mode and ingredients not yet confirmed."

We are a filter, not a doctor. Disclaimers throughout. The data model
makes the disclaimer truthful.

## Cost target

Under $0.25 per 50-item menu, end-to-end (extract + resolve + tag).
Prompt-cached taxonomy is what makes this work.
