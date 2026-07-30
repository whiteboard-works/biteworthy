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

Vision-capable Claude reads the input directly (no OCR step). This is
the pipeline's one heavyweight LLM call. (The extraction prompt does
**not** carry the taxonomy — that belongs to the gap-fill stage below.)

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
          "prices": [{ "size": null, "price_cents": 450 }],
          "addons": [{ "name": "guacamole", "price_cents": 200 }]
        }
      ]
    }
  ]
}
```

Add-on/upsell lines ("Add guacamole $2") are classified by the model
and nested under the dish they modify (`addons`, optional) — they must
never surface as standalone items. A deterministic backstop at
materialization catches stragglers: a top-level item whose name matches
`/\Aadd\s/i` folds into the previous item's `addons_payload`
(`source: "guard"`; the model's own nesting lands as
`source: "extract"`). The pattern is deliberately just the "Add …"
prefix — a false fold silently drops a dish, so anything more ambiguous
(trailing `+`, "extra") stays a card a human can reject.
First-in-section has no parent, so it stages as a normal item.

### 2. Resolve (deterministic — no LLM)

`ResolveItemsJob` resolves every item in-process, in seconds, against
the taxonomy already in Postgres:

- **Ingredient match** (`Ingestion::IngredientMatcher`): explicit
  mentions in the name/description matched against ingredient names +
  `aliases[]` — normalized, longest-phrase-first, plural-bridged. Name
  hit = confidence 1.0, alias hit = 0.95, `source: "match"`. The
  description is the ingredient authority; dish-name leftovers only
  count when the name is all the evidence there is.
- **Existing-item match** (`Ingestion::ExistingItemMatcher`): staged
  items are linked (`matched_item_id` + `match_score`) to the
  restaurant's existing Items so a re-scan stages updates instead of
  duplicates. Deterministic and greedy one-to-one: normalized-token
  equality (lowercase, punctuation stripped, singularized, stopwords
  dropped) wins at 1.0; otherwise pg_trgm `similarity() >= 0.60` with a
  token-subset veto — "Chicken Burrito" never matches "Chicken Burrito
  Bowl" no matter how similar, because a name whose token set strictly
  contains the other's is a different dish. Calibration data lives with
  the constant. A false merge corrupts a live item; a missed match is
  just a duplicate card a human can reject.
- **Tag derivation** (`Ingestion::TagDeriver`): one strategy per tag
  family. `allergen` derives from the resolved ingredients' ltree
  ancestry (`dairy.* → contains-dairy`, plus cross-root exceptions like
  oyster sauce → shellfish) — **the only code path that emits allergen
  tags**. `diet` is explicit menu claims with contradiction vetoes: a
  resolved meat suppresses "vegan"/"vegetarian", and a claim its own
  derived allergen tags contradict (wheat → no "gluten-free" badge) is
  dropped; never inferred from absence. `prep`/`flavor` are keyword
  tables. `cuisine` is a weak keyword pass, mostly delegated to
  gap-fill.

The run transitions to `staged` right here — the verify UI gets
populated dishes seconds after extraction.

### 2b. Gap-fill (one background LLM call)

Items the resolver flags as gaps (nothing matched, unknown leftover
phrases, or a composite condiment like "caesar dressing") get ONE
Haiku call after staging — `GapFillResolveJob`, tracked by
`ingestion_runs.enrichment_status` (`pending | completed | failed`).
The prompt carries the **prompt-cached** ingredient catalog plus the
cuisine-family tag catalog only, and asks solely for what code can't
do: implied ingredients ("Caesar Salad" → anchovy, egg) and cuisine
tags. Merge rules: append-only (`source: "ai"`), unknown slugs
dropped, only items still `pending`, and allergen/diet tags re-derived
in code over the merged ingredient set. A gap-fill failure never fails
the run — it's already staged and usable on deterministic data.

### 3. Stage

Items are materialized at extract time (empty payloads); resolve and
gap-fill enrich them in place. Every payload row carries provenance:

```ruby
ingredients_payload: [
  { slug: "meat-beef",    confidence: 1.0,  source: "match" },  # deterministic
  { slug: "fish-anchovy", confidence: 0.85, source: "ai"    },  # gap-fill
],
tags_payload: [
  { slug: "contains-fish", confidence: 0.85, source: "ai"      }, # derived from the AI ingredient
  { slug: "grilled",       confidence: 0.9,  source: "match"   },
]
```

(`source: "derived"` marks a tag derived from a deterministic
ingredient's ancestry.) Matched items serialize a `match` block
(existing item + a serialize-time diff: description, prices, added
ingredients/tags) for the verify UI. **Known gap**: accepting a
matched item still creates a duplicate — the apply-update-on-accept
path is the next PR in the re-scan arc.

### 4. Verify

Contributor opens a swipe UI:

- ✅ Accept → `IngestionItem.decision = 'accepted'`, promote to a real
  `Item` with `confidence = 'confirmed'`. Each `addons_payload` row
  becomes an `ItemModifier` (`kind: "addition"`, name + price) on the
  new Item; each priced `prices_payload` row becomes an `ItemVariant`
  (size + price_cents, payload order) — rows without a price are
  skipped.
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

Under $0.25 per 50-item menu, end-to-end. Resolve is free (pure code);
the only per-run LLM spend is extraction plus at most one gap-fill call
whose prompt-cached catalog prefix costs cents to read.
