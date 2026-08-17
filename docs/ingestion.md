# AI ingestion pipeline

The cold-start unlock. A contributor hands us a menu — a photo, a URL, or
pasted text — and within a minute the dishes are staged with ingredient and
tag suggestions. A short review and the restaurant is live.

The 2020 product needed a small army of Durango volunteers hand-typing
menus. v2 reduces that to a conversation. The AI does the typing; humans
do the verifying.

**Verification is a conversation, not a swipe deck.** The pipeline below is
driven by the ingestion tools in `app/services/tools/ingestion/` — over MCP,
or from the first-party chat. There is no `/ingest` UI and no REST ingestion
endpoint; both were removed when the tool layer landed. See `docs/mcp.md`.

## Inputs

| Input | Source |
|---|---|
| Photo | Mobile camera, multi-page capture |
| URL | Restaurant menu page on the web |
| PDF | Upload from web or mobile |

All three end up as ActiveStorage blobs attached to an `IngestionRun`.

## Stages

States: `queued → extracting → resolving → staged → published` (or `failed`
at any point). Each stage is idempotent and resumable.

The logic lives in services — `Ingestion::StartRun`, `ExtractRun`,
`ResolveRun` — with `ExtractMenuJob` / `ResolveItemsJob` / `GapFillResolveJob`
as thin Solid Queue wrappers around them.

**Dispatch is explicit at the call site.** `transition_to!` used to enqueue
the next job from an after-transition hook, which meant
`transition_to!(:extracting)` silently fired an Anthropic call and no call
site read as though it did. Each service now enqueues the next one itself.

Extraction runs in a job rather than inline because the vision call takes
tens of seconds — far too long to block a tool call or a chat turn.
`start_menu_scan` returns immediately and the caller polls `get_scan_status`.

### 1. Extract

Vision-capable Claude reads the input directly (no OCR step). This is
the pipeline's one heavyweight LLM call. (The extraction prompt does
**not** carry the taxonomy — that belongs to the gap-fill stage below.)

**Two schemas, one source.** The response is *constrained* by
structured outputs (`output_config.format`) and then *validated*
against the full schema. `Ingestion::SchemaForRequest.derive` produces
the wire form from `MenuExtractionSchema` by rewriting `oneOf` as
`anyOf` and dropping every keyword structured outputs reject — the list
lives in `SchemaForRequest::UNSUPPORTED` (`minLength`, `maxLength`,
`minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`,
`multipleOf`, `minItems`, `maxItems`, `pattern`, `format`). Derived
rather than hand-written because two schemas drift silently: a wire
schema missing a field still produces valid-looking output, just
without the field.

Keywords are only stripped where they *are* keywords. One level below a
`properties` key the same words are field names, so a property called
`format` survives while a `format:` constraint beside it does not.

The two schemas can disagree in exactly one direction, and it is worth
knowing rather than calling this lossless: a response with `"w": 0` or
`"name": ""` satisfies the grammar the model was constrained to and
then fails the full schema's `exclusiveMinimum` / `minLength`. That run
pays for output the API told the model was acceptable. Left to fail
rather than coerced — an empty dish name is bad data, and repairing it
quietly would publish a nameless dish instead of refusing one.

**`max_tokens` is 16,000, and the number matters.** It was the client's
shared 8,000 default, which was never chosen for the one caller that
emits a long structured document. A dense menu overran it and the run
was recorded as `schema_validation_failed`, because a response cut off
at the limit is *also* unparseable JSON — a message that says the model
wrote something wrong when it wrote something unfinished. Not the
model's 128,000 ceiling: `max_tokens` is the only thing bounding how
long one non-streaming call can take, and `ANTHROPIC_READ_TIMEOUT` is
240s, so a bigger cap trades a truncated response for a socket timeout.
Anything genuinely larger belongs in more than one call.

**Truncation is now its own failure.** `AnthropicClient` reads
`stop_reason` before parsing and raises `TruncatedError` on every
non-streaming call, schema or not; extraction records it as
`menu_too_large`, gap-fill as its own label, so "too big to do in one
pass" stops being reported as a schema problem and pointing at the
prompt. The streaming path (the chat, not ingestion) only **logs** it —
the answer is already on screen word by word, and replacing something
useful with an error is the wrong trade.

**The system prompt is not cached, and never was.** It carried
`cache: true` for months on ~976 tokens against Sonnet's 1,024-token
minimum, so Anthropic silently declined; every `IngestionRun` ever
recorded shows `cached_input_tokens: 0`. The flag is gone rather than
the prompt padded — a run costs ~0.3¢ of system prompt and scans are
rare enough that a 5-minute window rarely sees two.

Output (constrained on the way out, validated on the way in):

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
- **Implied bases** (`DeterministicResolver::IMPLIED_BASE_KEYWORDS`):
  composed-dish name keywords (pizza, burger, wrap, pasta, ramen, ...)
  union a base ingredient the description never states — today all map
  to `grain-wheat`, so a cleanly-resolved Margherita still carries its
  crust and `contains-gluten`. Unioned at confidence 0.8,
  `source: "derived"` (inferred, never presented as menu-stated), and
  skipped when an explicit match already covers the base's subtree. A
  keyword hit also routes the item to gap-fill regardless — the map
  catches the base, the model catches the rest (sauces, batters).
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

### 2b. Gap-fill (background LLM calls)

Items the resolver flags as gaps (nothing matched, unknown leftover
phrases, a composite condiment like "caesar dressing", or a
composed-dish name keyword) get Haiku calls after staging — one per
slice of 25 gap items, merged slice-by-slice — via `GapFillResolveJob`,
tracked by `ingestion_runs.enrichment_status`
(`pending | completed | failed`).
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
ingredients/tags); accepting one applies the diff to the existing Item —
see "Update flow (re-scan)" below.

### 4. Verify

A conversation, driven by these tools:

| Tool | Does |
|---|---|
| `list_staged_items` | The staged dishes, with resolved ingredients/tags, `confidence`/`source` on each, plus `unresolved` text and any `updates_existing_item` match. `needs_attention: true` narrows to the dishes whose filter data is wrong or empty. |
| `edit_staged_item` | Fix name / description / ingredients / tags / prices / add-ons. Lists replace wholesale; slugs must resolve. Sets `decision = 'edited'`; does not promote. |
| `accept_staged_items` | `decision = 'accepted'` and promote to a real `Item`. Each `addons_payload` row becomes an `ItemModifier` (`kind: "addition"`); each priced `prices_payload` row becomes an `ItemVariant` (size + price_cents, payload order) — rows without a price are skipped. |
| `reject_staged_items` | `decision = 'rejected'`; stays in the run for audit. Refuses a dish already promoted. |
| `undo_staged_item` | Back to pending, reversing what an accept did to the live menu. |

Confidence on promotion follows who accepted: admin → `confirmed`,
community contributor on their own run → `suggested`. See "Honest
disclosure" below.

On a MATCHED (re-scan) dish, `edit_staged_item` can still change add-ons but
`apply_update!` leaves modifiers alone, so the change won't reach the live
item — a v1 non-goal, listed below.

### 4b. Update flow (re-scan)

When the resolve pass matched a staged item to an existing Item
(`matched_item_id`), accept **applies the scan as an update** instead
of creating a duplicate (`IngestionItem#apply_update!`):

- **Description** — overwritten only when the scan carries one and it
  differs. Absence of evidence never blanks data.
- **Prices** — `ItemVariant` set replaced only when the scanned set is
  non-empty and differs.
- **Ingredients/tags** — append-only at accept-confidence
  (`source: "human"`); existing joins are **never removed or
  downgraded** by a scan.
- **Trust** — same model as creation: admin accept → `confirmed` joins;
  community accept → `suggested` joins, and if that adds unconfirmed
  data to a `confirmed` Item, the Item downgrades to `suggested`
  (strict-mode users must not see unvetted associations). Never
  upgraded here — graduation stays with the admin confirm-all.
- **Undo** — every change is snapshotted into
  `ingestion_items.applied_changes`; undo restores the snapshot
  (last-writer-wins over manual edits made in between) and the card
  returns to pending still linked as an update card. If the matched
  Item was deleted before accept, the FK nullifies the link and accept
  falls back to creating a fresh Item.
- **v1 non-goals** — item *name* (identity key, often human-curated),
  `ItemModifier`s, and photos are untouched on update; removal
  detection ("this dish left the menu") is deliberately out of scope.

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
the only per-run LLM spend is extraction plus the gap-fill calls (one
per 25 gap items) whose prompt-cached catalog prefix costs cents to
read.
