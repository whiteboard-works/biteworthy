# Phase 4.11 — Per-dish photo extraction (subplan)

A user-requested followup that didn't fit into the original Phase 4 queue. Many menus have photos of individual dishes inline on the page. Today the AI ingestion pipeline (Phase 2.3) extracts the *text* — name, description, prices — but throws the per-dish photo away. This phase pulls each dish photo out of the source page and attaches it to the resulting `Item`, so the restaurant page can render the menu with real food photos.

The infrastructure for image attachments is already in place: Phase 4.3 added `has_one_attached :photo` for `Review`, and `image_processing ~> 1.13` is in the Gemfile (used by ActiveStorage variants). This phase reuses both.

**Demo at the end:** open a restaurant page on web or mobile; items that had a photo on the source menu page render with the cropped photo alongside the name + description. Items that didn't (text-only menus) render unchanged.

## Stop conditions specific to Phase 4.11

- **`ANTHROPIC_API_KEY` daily cap** — recording the new bounding-box extraction cassette will burn ~5–10× the input tokens of the current `ExtractMenuJob` cassette (image bytes count fully against output for vision). The current Anthropic project's daily cap can hit again. If the loop's recording attempt 400s with "usage limit reached," pause + ping `@shadoath` per playbook §7.
- **Bbox accuracy is unproven** — Claude vision returns coordinates in *its* understanding of the image. The crop may be slightly off-center or include adjacent UI text. Acceptance criterion below sets a deliberately lenient bar (visual sanity-check on 3 different menu images) rather than pixel-perfect. If accuracy is unacceptable, the fallback is to skip auto-crop and just save the bbox so the admin can drag-adjust during swipe-verify (out of scope for 4.11; tracked as a Phase 5+ enhancement).
- **Cost increase** — bboxes add ~10–20% to output tokens per page. Phase 2.9's cost dashboard will reflect it. The "$0.25 per 50-item menu" target may slip to ~$0.30; acceptable for v1 launch but worth tracking.

## Prerequisites

**Phase 4.11.0 — Record the existing cassette first** (`claude/cassette-extract-menu-job` branch already prepped, blocked on the API cap from earlier). This isn't strictly part of 4.11 — it's the deferred Phase 2.3 cassette work — but it should land first so the new bbox-cassette work doesn't compound a stale baseline.

## Tasks (one PR each)

### 4.11.1 — Schema + ImageCropper service

**Branch**: `claude/phase-4.11.1-image-cropper`

- Migration: add `image_bbox jsonb` to `ingestion_items` (`{x, y, w, h}` as floats in 0..1, fractions of the source page so the crop is resolution-independent).
- New `Ingestion::DishPhotoCropper` service. Takes a source `ActiveStorage::Blob` (the menu page) + a normalized bbox; returns a cropped JPEG via `image_processing` (uses `MiniMagick` under the hood). Pads the bbox by 5% to soak up minor coordinate drift from the model.
- Pure unit specs against committed fixture images (the menu sample at `apps/api/spec/fixtures/menus/sample.jpg` from the cassette PR).

**Acceptance**: cropping a known-good bbox on `sample.jpg` produces a JPEG that visually contains the intended dish (asserted via dimension checks + mean-color heuristic, not pixel-perfect comparison).

### 4.11.2 — Extend `ExtractMenuJob` to ask for + receive bboxes

**Branch**: `claude/phase-4.11.2-extract-bboxes`

- `MenuExtractionSchema` gains an optional `image_bbox` per item: same `{x, y, w, h}` shape (fractions). `additionalProperties: false` stays — Anthropic must return it OR omit it; nothing in between.
- `ExtractMenuPrompt::SYSTEM_INSTRUCTIONS` gets one paragraph telling the model: "If the item has an associated photo on the page, return its normalized bounding box as `image_bbox: {x, y, w, h}` with 0,0 = top-left and 1,1 = bottom-right. Otherwise omit the field."
- After extraction, the staging `IngestionItem`s store the bbox (when present) in the new `image_bbox` column.
- New cassette recorded against `sample.jpg` — VCR's body matching means this auto-invalidates the cassette from 4.11.0; a fresh one captures both the original output AND the new bboxes.

**Acceptance**: replaying the new cassette ends with `IngestionItem.where.not(image_bbox: nil).count >= 3` for the Simply Tasty Thai appetizers page (Spring Rolls, Crab Rangoon, Chicken Satay all have inline photos).

**Stop**: needs `ANTHROPIC_API_KEY` recording. If capped, push the schema + prompt + spec stub and skip the live re-record like the Phase 2.3 cassette PR did.

### 4.11.3 — `IngestionItem#promote!` attaches the cropped photo

**Branch**: `claude/phase-4.11.3-promote-photo`

- `Item` gains `has_one_attached :photo` (mirrors `Review#photo` from 4.3).
- `IngestionItem#promote!` extension: if `image_bbox` is present, call `Ingestion::DishPhotoCropper` on the run's source blob + bbox, attach the result to the new `Item.photo`. If cropping fails (model returned weird coordinates, blob unreadable), log + skip — never blocks promotion.
- Items endpoint serializer emits `photo_url` per item (signed `rails_blob_url`, same `PUBLIC_HOST` env var the Phase 4.3 review photos use).

**Acceptance**: run-through-promote of a cassette-staged ingestion produces `Item.photo.attached?` for items with bboxes; items endpoint returns `photo_url: "https://..."` for them and `null` for the rest.

### 4.11.4 — Render dish photos on web + mobile restaurant pages

**Branch**: `claude/phase-4.11.4-render-photos`

- Web `RestaurantClient` and mobile `app/restaurants/[id].tsx` ItemRow render the `photo_url` when present (max-height 200px, `object-cover`, falls back to text-only row when null).
- The `RestaurantItem` type in `apps/web/src/lib/restaurants.ts` and `apps/mobile/lib/api/restaurants.ts` gains `photo_url: string | null`.
- One vitest + one jest case asserts the URL renders into an `<img>` / `<Image>` element when set, doesn't render when null.

**Acceptance**: user opens a restaurant page that was ingested through the 4.11.2 + 4.11.3 path → sees dish photos inline. Restaurants ingested before 4.11 (no bbox in their staging) show unchanged.

## Cross-cutting

- **Cost dashboard** — Phase 2.9's `/admin/dashboard` shows per-run `api_cost_cents`. After 4.11.2 lands, validate that the bump is in the predicted 10–20% range; if it's worse, revisit the prompt.
- **OpenAPI codegen** — `Item` payload gains `photo_url`; rerun `pnpm --filter @biteworthy/api-types build:codegen` and commit the regenerated `generated.ts`.
- **No mobile camera change** — Phase 2.6's mobile capture sends the menu page bytes unchanged; bboxes come back from the model regardless of input source.

## Out of scope for Phase 4.11

- Admin drag-to-adjust bboxes during swipe-verify — Phase 5+. The "AI got it close, human fine-tunes" UX is a real win but its own design problem.
- Restaurant gallery / hero photos — different schema, different upload path. Out of v1 entirely per `docs/roadmap.md`.
- Photo upload by admins on `/admin` — `Avo::Resources::Item` could gain a photo field, but it's noise unless a human's manually fixing AI extractions; defer until volume warrants.
- Per-item photo galleries (multiple photos per dish) — `has_one_attached`, not `has_many_attached`. v1 ships one.
