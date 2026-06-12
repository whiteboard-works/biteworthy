# Phase 8 — "Most likely to enjoy" taste ranking (subplan)

Phase 8 is the product's differentiator. Phases 1–7 answer "what CAN
I eat here?" (hard dietary safety). Phase 8 answers **"what WILL I
love here?"** — a taste lens that ranks the safe items and leads with
a Top Picks view, so a 60-item menu reads like an 8-item menu.

Design principle: **safety filters, taste ranks.** Avoid lists keep
hiding items (hard, existing behavior, untouched). Taste signals are
*soft* — they reorder and highlight, never hide. The two must stay
separate concepts in schema, API, and UI copy.

**Demo at the end:** two users with the same allergy profile open the
same restaurant. Both see the same safe items, but each sees a
different Top Picks row — one's love of spicy Thai curries vs the
other's burger habit — with a one-line "because you like…" explainer
per pick.

## Scoring model (v1 — deliberately simple)

```
score(item) =
    2.0 * |item.tag_ids ∩ liked_tag_ids|
  + 1.0 * |item.ingredient_ids ∩ liked_ingredient_ids|
  - 2.0 * |item.tag_ids ∩ disliked_tag_ids|
  - 1.0 * |item.ingredient_ids ∩ disliked_ingredient_ids|
  + 0.5 * normalized_popularity            (popularity / max_at_restaurant)
  + 0.5 * (avg_visible_rating - 3) / 2     (0 when unreviewed)
```

Weights are constants in ONE place per implementation (SQL + TS) with
a shared fixture test asserting both produce identical scores for the
same inputs. No ML, no embeddings, no per-user weight learning in v1
— the schema leaves room (signals are arrays, weights are code).

Top Picks = the N (default 5) highest-scoring *visible* items with
score > 0. Fewer than 3 positive-score items → no Top Picks row
(don't fake enthusiasm).

## Stop conditions specific to Phase 8

- The SQL ranking and the filter-engine TS ranking MUST land in the
  same PR as each other whenever either changes (repo rule), with the
  shared-fixture parity test.
- If ranking pressure tempts you to *hide* low-scoring items: stop.
  Taste never hides. Re-read the design principle.

## Tasks (one PR each)

### 8.1 — Taste signal schema + profile API

**Branch**: `claude/phase-8.1-taste-schema`

- Migration: `liked_ingredient_ids uuid[]`, `liked_tag_ids uuid[]`,
  `disliked_ingredient_ids uuid[]`, `disliked_tag_ids uuid[]` on
  `user_profiles` (default `{}`), GIN not needed (read-side only).
- `GET/PATCH /api/v1/profile` reads/writes the four arrays with the
  same validation pattern as the avoid arrays (UUIDs must exist).
- A value may not appear in both liked and disliked (validation).
- Avoid-vs-taste interaction: an id present in an avoid list is
  ignored by scoring (filter wins; no error).
- rswag + `bin/openapi-export` + api-types codegen in the same PR.

Specs: round-trip, both-lists validation error, avoid-overlap
ignored, unknown UUID rejected.

### 8.2 — Scoring engine (SQL + filter-engine, one PR)

**Branch**: `claude/phase-8.2-taste-scoring`

- `GET /api/v1/restaurants/:id/items` computes `taste_score` per the
  model above (SQL: cardinality of array intersections; ratings via
  the visible-reviews aggregate) and returns it per item, plus
  `taste_reasons` (which liked tags/ingredients matched, for the
  "because you like…" line). Sort: visible items by
  `taste_score DESC, popularity DESC, name ASC` when the caller has
  any taste signal; unchanged legacy sort otherwise.
- `packages/filter-engine`: `scoreItem(item, profile)` +
  `topPicks(items, profile, n=5)` mirroring the SQL exactly.
- Shared fixture: one JSON file of items+profiles checked into the
  filter-engine package; vitest asserts TS scores; an RSpec test
  loads the same JSON and asserts SQL scores match to 4 decimal
  places.
- rswag + openapi-export + codegen (response shape changed).

Specs: parity fixture, zero-signal no-op, dislike outweighs
popularity, unreviewed items get no rating term.

### 8.3 — Top Picks UI (web)

**Branch**: `claude/phase-8.3-web-top-picks`

- `/restaurants/[slug]`: when ≥3 positive-score items, render a
  "Top picks for you" row above the sections — card per pick with
  photo (Phase 4.11), name, price, and the one-line taste reason.
  Full menu below, unchanged except subtle score-ordered sections.
- Anonymous / no-taste-signal users see today's layout untouched.
- "Why these?" affordance explaining picks come from their likes.

Specs (vitest/RTL): row renders at ≥3 picks, absent below, reason
line text, anonymous unchanged.

### 8.4 — Top Picks UI (mobile)

**Branch**: `claude/phase-8.4-mobile-top-picks`

- Mirror 8.3 in `apps/mobile/app/restaurants/[id].tsx`: horizontal
  Top Picks cards above the section list; same thresholds and
  anonymous behavior.

Specs (jest/RTL): same coverage at screen level.

### 8.5 — Taste onboarding step (web + mobile)

**Branch**: `claude/phase-8.5-taste-onboarding`

- New onboarding step between strictness and review: "What do you
  love?" — tap-to-like cuisine/flavor tag chips (from the tag
  families) + optional ingredient search; long-press/secondary action
  marks dislike. Skippable — taste is optional, safety is not.
- Existing users: an "Improve my picks" entry on the profile screen
  reaches the same step standalone.
- PATCHes the Phase 8.1 fields.

Specs: chip toggle cycle (neutral → liked → disliked → neutral),
skip leaves arrays empty, PATCH payload shape.

## Cross-cutting

- Analytics: add optional properties (e.g. `top_picks_shown`,
  `taste_signal_count`) to existing events only — no event renames.
- Copy must never imply a low-scored item is unsafe — taste ≠ safety.

## Out of scope for Phase 8

- Learning weights from behavior (taps, reviews, overrides) — future.
- Collaborative filtering / "people like you" — future.
- Per-restaurant cuisine inference beyond existing tags.
