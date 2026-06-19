# Phase 3 — Dietary filter UI (subplan)

Phase 3 ships the actual user-facing payoff of everything Phase 1 + 2
built. The server-side filter (Phase 1.7) and the catalog
(Phase 1.4 + the AI ingestion of Phase 2) finally land in front of
real diners on web + mobile.

`docs/schema.md` documents the underlying SQL filter; this phase
wraps it in a friendly UI on both surfaces.

**Demo at the end:** open the app, pick "Celiac + tree-nut allergy"
in onboarding, scan a real Durango menu, see only the dishes that
pass. Hidden items each say *why* ("contains gluten (wheat)";
"contains tree nut (almond)"). Tap "show anyway" on one and it
re-appears immediately without a server round trip.

## Stop conditions specific to Phase 3

- **Phase 2 cassette gap** still applies if any Phase 3 task wants to
  ingest a *fresh* menu end-to-end during testing. Pre-existing
  IngestionItems + handcrafted Items work fine for filter UI work.
- **Web auth gap**: `/ingest` and (in this phase) `/restaurants/:id`
  still ask the user to paste a JWT until Phase 4 ships proper
  cookie sessions. Acceptable for Phase 3 since the dietary filter
  endpoint (`GET /restaurants/:id/items`) is unauthenticated by
  design — anonymous browsing is part of the demo.

## Tasks (one PR each)

### 3.1 — Production-ready dietary profile seeds

**Branch**: `claude/phase-3.1-dietary-profile-seeds`

The factory has the names (Vegan, Vegetarian, Pescatarian, Celiac,
Gluten-Free, Dairy-Free, Halal, Kosher, Tree-Nut Allergy, Peanut
Allergy) but `db/seeds/dietary_profiles.yml` is empty.

This PR populates it: each preset gets a curated `avoid_ingredient_slugs`
+ `avoid_tag_slugs` list referencing real entries from the 1,096-row
ingredient catalog (#131) and the tag families. Plus a one-line
description for the onboarding card UI.

Seed-task spec asserts:
- All 10 presets load idempotently.
- "Vegan" avoids the `dairy.*`, `egg.*`, `meat.*`, `poultry.*`, `fish.*`,
  `shellfish.*` subtrees AND the `allergen.contains_dairy` /
  `allergen.contains_egg` tags.
- "Celiac" avoids gluten-bearing grains (wheat, rye, barley, spelt)
  + the contains-gluten tag.

### 3.2 — Mobile profile onboarding (6 taps)

**Branch**: `claude/phase-3.2-mobile-onboarding`

New screen `app/onboarding/index.tsx`:
1. "What can't you eat?" — preset chip picker (Vegan, Celiac, etc.).
   Multi-select; each pick unions the preset's avoid lists into the
   draft profile (additive).
2. "Anything else?" — free-text search over the ingredient catalog;
   tap to add to avoids.
3. "How strict?" — relaxed / balanced / strict toggle.
4. "Done" — POSTs to `PATCH /api/v1/profile` (Phase 1.3 endpoint),
   stores the JWT in `expo-secure-store`, navigates to a city/
   restaurant picker.

Specs: Jest unit tests for the draft-profile reducer; one snapshot
per screen.

### 3.3 — Mobile filtered restaurant page

**Branch**: `claude/phase-3.3-mobile-restaurant-page`

`app/restaurants/[id].tsx`:
- Calls `GET /api/v1/restaurants/:id/items` with the user's JWT
  (server applies `current_user.profile` automatically per Phase 1.7).
- Renders sections + items. Visible items first; hidden items below
  in a collapsed "Items hidden by your filter (N)" expander.

Specs: API client function + screen render snapshot.

### 3.4 — Transparency layer + one-tap override

**Branch**: `claude/phase-3.4-transparency-and-override`

Hidden items render a `<HiddenReasonChip>` per reason — translates
the `{kind, ingredient_id|tag_id}` shapes from Phase 1.7 into
human strings ("Hidden — contains dairy (Cheese)").

"Show anyway" button on each hidden item flips its local state to
visible WITHOUT a server round-trip. The override applies for the
session only; it doesn't mutate `UserProfile` (Phase 4 adds a
"never hide this dish" persistent override).

Specs: chip rendering for each kind + overridden-item snapshot.

### 3.5 — Strict-mode toggle

**Branch**: `claude/phase-3.5-strict-mode-toggle`

A persistent toggle in the restaurant header — defaults to whatever
`current_user.profile.strictness` is, but flipping it sends
`?strictness=strict` (or `relaxed`) on the next items refetch.

Spec: API roundtrip + UI snapshot.

### 3.6 — Web filtered restaurant page + transparency + strict toggle

**Branch**: `claude/phase-3.6-web-restaurant-page`

Mirrors 3.3 + 3.4 + 3.5 on Next.js. Server-rendered (SSR) for the
SEO city pages (`/durango/gluten-free`, etc., scheduled for Phase 5
but the per-restaurant page is a Phase 3 building block).

`/restaurants/[slug]` page (note: slug, not id — for SEO).

Specs: vitest + RTL render tests.

### 3.7 — `applyProfile` in filter-engine

**Branch**: `claude/phase-3.7-filter-engine-apply-profile`

Move the per-item filter+reasons computation from
`Api::V1::ItemsController` (Phase 1.7) into
`packages/filter-engine`. The Rails endpoint keeps doing the SQL
pre-filter (`items && avoid_ids` overlap) — that part isn't
client-runnable. But the per-item reason computation runs the same
on Ruby + TS, so client-side "show anyway" doesn't need a server
roundtrip and SSR can render the hidden-state without re-querying.

Spec coverage: the existing filter-engine vitest + new ones for the
reason payloads.

### 3.8 — Web profile onboarding (mirror of 3.2)

**Branch**: `claude/phase-3.8-web-onboarding`

Same flow as mobile, Next.js + Tailwind. JWT lands in a cookie
(short-term workaround until Phase 4's real session cookie).

### 3.9 — Shareable filter URLs

**Branch**: `claude/phase-3.9-shareable-filter-urls`

`/r/:slug?p=<base64-encoded-profile>` — anyone with the link sees
the menu pre-filtered to the encoder's profile, without needing to
sign in. The encoder's own profile is unaffected.

Backend support: `?profile_token=<base64>` on
`/api/v1/restaurants/:id/items` decodes to the same shape as the
DietaryProfile preset filter from Phase 1.7. Backwards-compatible
with `?profile=<slug>`.

Specs: encode/decode round-trip; controller spec for the new param;
web + mobile share button.

## Cross-cutting

- **Telemetry hooks (PostHog stubs)**: Phase 5 wires real PostHog,
  but the events `app_open`, `profile_set`, `menu_filtered`,
  `restaurant_tap` should fire from the right places now so the
  Phase 5 wiring is one config line. Each task above adds the
  matching `track(...)` call as it lands the surface.

## Out of scope for Phase 3

- "Never hide this dish" persistent override (Phase 4 — same flag
  belongs with reviews + saved-menu history).
- City filter pages (Phase 5 SEO).
- Real PostHog wiring (Phase 5).
- Restaurant search picker (Phase 4 — comes with the contributor
  account flow).
