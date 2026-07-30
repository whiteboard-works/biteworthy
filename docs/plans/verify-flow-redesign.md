# Verify-flow redesign (Phase 2 "one flow")

## Context

The scan → verify flow works, but the UX is weak (surfaced testing RGP's Wraps —
37 items in a flat list, ~40s of "Matching ingredients…" before anything shows).
The owner asked for, as one cohesive redesign:

1. **Instant dishes** — a "basic LLM given a website/photo can extract dishes
   very quickly," so show them fast; do ingredient/tag matching in the background.
2. **Wait for enrichment after approvals** — you can approve dishes immediately,
   but publishing waits until matching finishes (the dietary filter needs
   ingredients/tags — an `Item` must never go live without them).
3. **Group by sub-menu** — lay verify items out by their section.
4. **Accept All** — bulk-accept every pending item.
5. **Undo** — reverse an accept.

## The load-bearing mechanic: *when a dish becomes a real `Item`*

`IngestionItem#promote!` builds the real `Item` + `ItemIngredient`/`ItemTag` joins
from `ingredients_payload`/`tags_payload`. **Promote must not run before those
payloads are filled** — otherwise a dish goes live with no ingredients/tags and
the filter can't protect a celiac/allergic user. That is the safety invariant the
whole redesign turns on.

Today: extract → resolve ingredients → resolve tags → **materialize items** →
staged → verify shows them → accept calls `promote!` (payloads already present).

New: extract → **materialize items now (empty payloads)** → resolve fills payloads
in the background → verify shows dishes immediately → accept is allowed but
`promote!` is **deferred** until the item is enriched.

## State model (no new DB states)

`extracting` → `resolving` → `staged` → `published`, but with new meaning:

- **resolving** = dishes exist + are visible; ingredients/tags are being matched.
  "Enriched" is a per-**run** property (resolve does all items in 2 batch calls),
  so during `resolving` every item shows "matching…"; at `staged` all are enriched.
- **staged** = fully enriched; any accepted-during-resolving items get promoted.

## Backend

### Migration
- `add_column :ingestion_items, :position, :integer` (nullable; new runs set it,
  old rows stay null). Resolve maps its indexed results back to items by position.

### ExtractMenuJob
- After writing `staging`, **materialize `IngestionItem` rows** (name, description,
  prices_payload, section_name, image_bbox, `position` = flat index; empty
  ingredient/tag payloads; decision `pending`), then transition to `resolving`.

### ResolveIngredientsJob / ResolveTagsJob (in `ResolveStageJob`)
- Prompt still built from `staging` (flat order). After the call, **update each
  `IngestionItem` by `position`** with its resolution:
  - ingredients job → `ingredients_payload`, `unresolved_ingredients`
  - tags job → `tags_payload`, `unresolved_tags`
- ResolveTagsJob (last), inside a transaction: **batch-promote** items already
  `decision: accepted` with `item_id` nil (accepted during resolving), then
  `maybe_publish!`, then transition to `staged`. Batch-promote uses `run.user` as
  `decided_by` (community self-verify's normal case → `suggested`; admin-owned run
  → `confirmed`). Edge case — a *different* admin accepting a community run during
  resolving lands `suggested` (safe; admins re-confirm via Phase 6.4). *(Drop the
  old `materialize_ingestion_items!` — items already exist.)*

### Accept / defer-promote (IngestionItemsController#update)
- decision `accepted`: if run enriched (`staged?`/`published?`) → `promote!` now;
  else record `decision: accepted` + `decided_at`, **no promote** (item_id stays
  nil). `maybe_publish!` already requires `staged?`, so no publish during resolving.

### Accept All — `POST /ingestion_runs/:id/items/accept_all`
- Accept every `pending` item in one transaction (same defer-or-promote rule),
  then `maybe_publish!`. Returns the updated items.

### Undo — `POST /ingestion_runs/:id/items/:id/undo` (or `decision: pending`)
- Revert an accepted item to `pending`: if promoted (`item_id` present), destroy
  the `Item` (cascades to `item_ingredients`/`item_tags`) and null `item_id`;
  clear `decided_at`. Pre-publish scope; if the run had published, the item is
  removed from the live menu (run stays published). Re-`maybe_publish!` is a no-op
  downward (we don't un-publish the run).

### Run payload
- Expose `staged_item_count` (dishes found) so the verify header can say "N dishes"
  during resolving. `enriched` = `status in [staged, published]`.

## Frontend — verify page (`/ingest/verify/[runId]`)

- Fetch items as soon as they exist (status `resolving` OR `staged`), not only
  `staged`.
- **Group by `section_name`** with sub-menu headers; ungrouped/nil section last.
- Per item: name + price always; ingredient/tag chips show **"matching…"** while
  `status == resolving`, then the resolved chips at `staged`.
- **Accept All** button (calls accept_all); **Undo** on accepted rows.
- Publish messaging: "Accept ≥80% to publish — publishing finalizes once matching
  finishes." Publish only fires at `staged`.
- Fold in the earlier progress idea lightly (dish count + stage label).

## PR breakdown (incremental, each shippable + tested)

1. **PR-1 backend pipeline** — position migration; materialize-at-extraction;
   resolve-updates-items-in-place; defer-promote + batch-promote-on-staged. The
   safety-critical core. Heavy specs on promote-timing + filter correctness.
2. **PR-2 backend endpoints** — Accept All + Undo.
3. **PR-3 web** — verify page redesign (grouping, instant dishes, matching status,
   Accept All, Undo, publish messaging).

Mobile verify screen mirrors PR-3 as a follow-up.

## Safety checklist (must hold at every step)
- No `Item` is ever created (`promote!`) before its `ingredients_payload`/
  `tags_payload` are populated.
- Publish (`maybe_publish!`) only fires when the run is `staged` (fully enriched).
- Undo fully removes the promoted `Item` + joins (no orphan live items).

## Addendum (2026-07-29) — deterministic resolve supersedes "staged = fully enriched"

The resolve stage was reworked (see `docs/ingestion.md`): `staged` now
means **deterministically enriched** — explicit-mention ingredients +
code-derived tags land in seconds, and a single background LLM
gap-fill (`enrichment_status` on the run) trails after, appending
implied-ingredient/cuisine suggestions to still-pending items only.
Consequences for the checklist above:

- Promote-before-payloads still can't happen (payloads are written in
  the same transaction that stages the run).
- `maybe_publish!` still only fires at `staged`, but "fully enriched"
  is no longer implied — an item accepted before gap-fill completes
  ships with deterministic (explicit-mention) data only; the verify UI
  shows "AI double-check still running" while `enrichment_status` is
  `pending`.
