# Phase 6 — Anyone-can-scan ingestion (subplan)

Phase 6 turns the admin-only ingestion pipeline (Phase 2) into the
community feature the product vision demands: **any signed-in user can
walk into a restaurant that isn't in the system, scan its menu, verify
the extraction, and publish it** — without an admin in the loop, and
without compromising the strict-mode safety guarantees.

The pipeline itself doesn't change. What changes is who may invoke it,
what trust level their output lands at, and the guardrails (quotas,
cost ceilings, duplicate detection, moderation visibility) that make
opening it safe.

**Demo at the end:** a brand-new non-admin account creates "Maria's
Tacos" with an address, uploads a menu photo, swipe-verifies the
staged items, and the restaurant goes live with every item visible to
relaxed/balanced users — while strict-mode users see nothing until an
admin confirms the associations. A second user scanning the same menu
gets a "did you mean Maria's Tacos?" dedup prompt instead of creating
a duplicate.

## Trust model (read before any task)

The existing columns do the heavy lifting — no new trust machinery:

- `ItemIngredient`/`ItemTag` rows carry `confidence` + `source`.
- Admin-verified promotions stay `confidence: confirmed, source: human`.
- **Community-verified promotions land `confidence: suggested,
  source: human`.** Strict-mode users only see fully-confirmed items,
  so community data is live for relaxed/balanced users and invisible
  to strict users until an admin (or restaurant owner, Phase 4.9)
  confirms it. This is the honest-disclosure contract extended to
  community data — do not weaken it.

## Stop conditions specific to Phase 6

- Quota/cost limits must be env-tunable with safe defaults; if a task
  finds itself hard-coding a dollar amount, stop and parameterize.
- If opening an endpoint requires loosening an auth check whose other
  callers you don't understand, stop and map the callers first
  (CLAUDE.md Rule 6).

## Tasks (one PR each)

### 6.1 — Non-admin ingestion runs + quotas + cost ceiling

**Branch**: `claude/phase-6.1-community-ingestion-access`

- Drop `ensure_admin!` from `POST /api/v1/ingestion_runs`; any
  authenticated user may create a run. `GET` show already permits
  owner-or-admin; keep that.
- Per-user quota: max `INGESTION_RUNS_PER_USER_PER_DAY` (default 5)
  non-admin runs per rolling 24h. 429 with a clear error payload when
  exceeded. Admins bypass.
- Global cost ceiling: if the sum of `api_cost_cents` across runs
  created in the current UTC day exceeds
  `INGESTION_DAILY_COST_CEILING_CENTS` (default 2000 = $20), non-admin
  run creation returns 503 with a "try again tomorrow" error. Admins
  bypass.
- Update the rswag spec for the endpoint; re-run `bin/openapi-export`
  + api-types codegen in the same PR (CI checks drift).

Specs: quota boundary (5th ok, 6th 429), admin bypass, cost ceiling
trip + reset, anonymous still 401.

### 6.2 — Community restaurant creation + duplicate detection

**Branch**: `claude/phase-6.2-community-restaurant-create`

- New `POST /api/v1/restaurants` (authenticated): `name`, `city_slug`,
  optional address fields. Creates a `draft` restaurant recording the
  creating user (`created_by_user_id` — new nullable FK column, new
  migration).
- **Dedup guard** (pg_trgm is already enabled): before create, check
  `similarity(restaurants.name, $name) > 0.55` among restaurants in
  the same city. On match, respond 409 with the candidate list
  (id, slug, name, address) so clients can offer "did you mean…?".
  `force: true` param overrides after the client has shown the prompt.
- `POST /api/v1/ingestion_runs` accepts the resulting restaurant_id
  from a draft restaurant the caller created (it must already — verify
  + spec the ownership check: non-admins may only target draft
  restaurants they created OR published restaurants, for re-scans).
- rswag + openapi-export + codegen in the same PR.

Specs: create happy path, dedup 409 with candidates, force override,
cross-city same-name no-collision, non-owner targeting another user's
draft restaurant 403.

### 6.3 — Self-verify + community-trust promotion

**Branch**: `claude/phase-6.3-community-self-verify`

- Allow a run's creator (not just admins) to `GET` + `PATCH` its
  ingestion items (accept/reject/edit). Other non-admin users: 403.
- `IngestionItem#promote!` learns who is promoting: admin deciders
  keep `confidence: confirmed`; non-admin deciders write
  `confidence: suggested, source: human` on the created
  `ItemIngredient`/`ItemTag` rows (see Trust model above). The Item's
  own `confidence` column follows the same rule.
- `maybe_publish!` (80% threshold) works unchanged for community runs:
  restaurant + items go `published` — visible to relaxed/balanced,
  invisible to strict until confirmed.
- rswag + openapi-export + codegen.

Specs: creator can decide own run / stranger 403; promotion writes
suggested for non-admin and confirmed for admin; strict-mode filter
hides a community-published item end-to-end (request spec against
`GET /restaurants/:id/items?strictness=strict`).

### 6.4 — Community-publish moderation visibility

**Branch**: `claude/phase-6.4-community-moderation-queue`

Admins need to *see* what the community publishes without gating it.

- Avo: scope/filter on restaurants + ingestion runs surfacing
  "community-published in the last 30 days" (created_by_user_id
  present, published via a non-admin run).
- Admin one-click "confirm all" action on a community-published
  restaurant: flips its items' `suggested` associations to
  `confirmed` (audit trail: source stays `human`). This is how a
  community menu graduates to strict-mode visibility.
- Counters on `/admin/dashboard`: community runs today, cost spent
  today vs ceiling.

Specs: confirm-all action flips associations + item confidence;
dashboard counters compute correctly.

### 6.5 — Web: community scan entrypoint

**Branch**: `claude/phase-6.5-web-community-scan`

- `/ingest` opens to any logged-in user (remove the admin gating in
  the page/proxy); logged-out users get a login redirect with
  `?next=/ingest`.
- New-restaurant step: name + city + address form, calling
  `POST /api/v1/restaurants`; render the 409 dedup candidates as
  "did you mean?" cards (pick one → reuse, or "create anyway").
- After upload: poll run status (existing pattern), then a simple
  web verify page (list items, accept/reject/edit inline — the web
  twin of mobile's swipe-verify, table layout is fine).
- Quota/cost errors (429/503) render human messages.

Specs (vitest/RTL): form validation, dedup-candidate rendering, verify
list accept/reject wiring, error states.

### 6.6 — Mobile: community scan entrypoint

**Branch**: `claude/phase-6.6-mobile-community-scan`

- Mirror 6.5 in the Expo app: `/ingest` available to any logged-in
  user; new-restaurant form screen ahead of capture; dedup prompt;
  swipe-verify (already built, Phase 2.7) reachable by the run
  creator; quota/cost error states.

Specs (jest/RTL): same coverage as 6.5 at the screen level.

## Cross-cutting

- Analytics: fire existing funnel events where they apply; add new
  optional-field payloads only (renaming events is forbidden —
  packages/analytics contract).
- Every API change: rswag spec + `bin/openapi-export` + codegen in the
  same PR.

## Out of scope for Phase 6

- Reputation/karma levels (explicitly out of v1 scope).
- Re-scan merge/update of an existing published menu (Phase 7.3 covers
  the UX entry; deep menu-diff merging is its own future phase —
  re-scans create a new run whose promoted items replace by exact
  name match only).
- Taste ranking (Phase 8).
