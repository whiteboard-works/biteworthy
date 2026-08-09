# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Working rules

These apply to every task unless explicitly overridden. Bias: caution over speed
on non-trivial work. Use judgment on trivial tasks.

### Rule 1 — Think, checkpoint, fail loud
State assumptions explicitly. If uncertain, ask rather than guess. Stop when
confused and name what's unclear. After each significant step, summarize what
was done, what's verified, what's left. "Completed" is wrong if anything was
skipped silently; "tests pass" is wrong if any were skipped. Default to
surfacing uncertainty, not hiding it.

### Rule 2 — Simplicity first
Minimum code that solves the problem. Nothing speculative. No features beyond
what was asked. No abstractions for single-use code. Test: would a senior
engineer say this is overcomplicated? If yes, simplify.

### Rule 3 — Surgical changes
Touch only what you must. Clean up only your own mess. Don't "improve" adjacent
code, comments, or formatting. Don't refactor what isn't broken.

### Rule 4 — Goal-driven execution
Define success criteria. Loop until verified. Strong success criteria let you
loop independently.

### Rule 5 — Use the model only for judgment calls
Use the LLM for: classification, drafting, summarization, extraction. Do NOT
use it for: routing, retries, deterministic transforms. If code can answer,
code answers. (Relevant to the ingestion pipeline — see `docs/ingestion.md`.)

### Rule 6 — Read before you write
Before adding code, read exports, immediate callers, shared utilities. "Looks
orthogonal" is dangerous. If unsure why code is structured a way, ask.

### Rule 7 — Tests verify intent, not just behavior
Tests must encode WHY behavior matters, not just WHAT it does. A test that
can't fail when business logic changes is wrong.

### Rule 8 — Surface conflicts, don't average them
If two patterns contradict, pick one (more recent / more tested), explain why,
and flag the other for cleanup. Don't blend conflicting patterns. Conformance
to existing repo convention wins inside this codebase — if you think a
convention is harmful, surface it; don't fork silently.

### Rule 9 — Keep the tracking docs current as work changes
The docs under `docs/` are the project's memory; treat them as part of the
change, not an afterthought. In the same PR that ships work: tick the item in
`docs/roadmap.md` (and add a `docs/status.md` line for anything non-trivial),
update any plan/checklist whose state changed, and fix doc facts the change
made stale (paths, infra, contracts). When a phase or plan fully ships, move
its subplan to `docs/plans/archive/` and collapse its detail out of the living
roadmap into the archive — the living docs should show what's left, not relitigate
what's done. A doc that lies is worse than no doc; if you can't verify a claim,
soften or flag it rather than leaving it stale.

---

## Stack at a glance

Pnpm + Turborepo monorepo. Three apps + five shared packages:

- `apps/api` — Rails 8 (Ruby 3.3.6) JSON API on Postgres 16. **Not** part of the pnpm workspace; lives as its own Bundler tree.
- `apps/web` — Next.js 15 App Router + Tailwind. Dev port `:3001`.
- `apps/mobile` — Expo SDK 56 + expo-router.
- `packages/api-types` — TS types codegen'd from `docs/openapi.json` (see Cross-package contracts below).
- `packages/filter-engine` — pure-TS dietary filter, shared by web + mobile, with Vitest tests. Mirrors the server-side SQL.
- `packages/analytics` — the funnel-event taxonomy (`EVENTS` map + `EventPropsMap`; 9 core funnel/engagement events + 3 auth events). Event names/payloads are a contract with the launch dashboards — **renaming an event breaks downstream funnels**; add new events + optional fields freely. `docs/analytics.md` documents each event; when doc and types disagree, the types win.
- `packages/ui-tokens` — design tokens consumed by Tailwind (web) and `StyleSheet.create` (mobile).
- `packages/eslint-config` — minimal flat config; framework rules live per-app.

`pnpm-workspace.yaml` covers `apps/web`, `apps/mobile`, `packages/*`. `apps/api` is intentionally excluded.

`_legacy/` is the frozen 2020 Rails 4.2 codebase. **Read-only** — never edit.

## Commands

From the repo root:

```bash
pnpm install               # install JS deps for the workspace
pnpm dev                   # turbo: boots web + mobile in parallel (api is separate, see below)
pnpm build                 # turbo build across packages + apps
pnpm typecheck             # turbo typecheck
pnpm lint                  # turbo lint
pnpm test                  # turbo test (Vitest for packages/web, Jest for mobile)

pnpm api <script>          # alias for: pnpm --filter @biteworthy/api ... (no JS scripts yet — use bin/rails)
pnpm web <script>          # alias for: pnpm --filter @biteworthy/web ...
pnpm mobile <script>       # alias for: pnpm --filter @biteworthy/mobile ...
```

The fastest path is the containerized stack — `docker compose up` (from the
repo root) boots the API on `:3000`, the Solid Queue worker, and Postgres,
with `apps/api` bind-mounted for hot reload. `docker compose up -d postgres`
still starts Postgres alone if you'd rather run the API natively. See
`docs/local-dev.md` for the full guide.

The API has its own toolchain — run from `apps/api/` (native path):

```bash
docker compose up -d postgres           # (from repo root) local Postgres 16, localhost-only, trust auth
bundle install
bin/rails db:prepare                    # create + load schema + seed (idempotent)
bin/rails s -p 3000                     # API on :3000 (web is on :3001)
bin/rails solid_queue:start             # Solid Queue worker (or boot inline: SOLID_QUEUE_IN_PUMA=true bin/rails s)
bundle exec rspec                       # full test suite
bundle exec rspec spec/requests/foo_spec.rb     # one file
bundle exec rspec spec/requests/foo_spec.rb:42  # one example by line
bundle exec rubocop --parallel
bundle exec brakeman --no-pager --quiet --format plain
bin/openapi-export                      # regenerate docs/openapi.json from the rswag specs
```

Inside the containerized stack the same commands run via
`docker compose exec api …` (e.g. `docker compose exec api bundle exec rspec`).

Per-app test runners (use these for narrow runs instead of `pnpm test`):

```bash
pnpm --filter @biteworthy/filter-engine test
pnpm --filter @biteworthy/web test
pnpm --filter @biteworthy/mobile test
```

Postgres needs the `ltree`, `pg_trgm`, `pgcrypto`, and `citext` extensions — the migrations enable them, but the role needs `CREATE EXTENSION` the first time.

## Architecture: the filter is the product

The schema is shaped around one question: "given a user's avoid lists, which items at this restaurant can they eat — and *why not* for the rest?"

**The filter does not run in SQL, and it never removes rows.** `ItemsController#index` loads every published item at the restaurant in one query, then computes a per-item `reasons[]` in Ruby (array intersection against the avoid lists, plus the strict-mode confidence check). Items with a non-empty `reasons[]` come back as `status: "hidden"` with the reasons attached. That is the honest-disclosure contract: a hidden item must always be able to say why it's hidden, so it has to survive the query.

Ranking is separate. When the signed-in user has taste signals, `TasteScoring.scores_for` runs one SQL query per restaurant (liked/disliked overlap ± popularity ± average visible rating) and the response is re-sorted by `taste_score`. Otherwise the order is `popularity DESC, name ASC`. Nothing sorts by `user_profiles.prefer_tag_ids`.

The array-overlap SQL does exist, just not here — `Cities::RestaurantRanking` uses `NOT (items.ingredient_ids && ARRAY[…]::uuid[])` inside a `COUNT(…) FILTER` to rank a city's restaurants by how many dishes pass a preset, in one query instead of 30 calls to the items endpoint.

Two consequences that affect almost every change in `app/models/item*.rb`:

1. **Items carry denormalized `ingredient_ids uuid[]` and `tag_ids uuid[]`.** The Ruby filter, `TasteScoring`, and `Cities::RestaurantRanking` all read them, which is what keeps a restaurant page to a couple of queries instead of a join per item. The `ItemIngredient` and `ItemTag` join tables are the source of truth + audit log; `after_save`/`after_destroy` callbacks on the joins keep the arrays in sync. **Never write to the arrays directly** — write to the joins. **Reading them has a trap**: `item.ingredient_ids` resolves to the has_many-through reader, which shadows the identically-named column and costs a query per item — use `item.denormalized_ingredient_ids` / `denormalized_tag_ids` unless you actually need the join rows.
2. **Every join row has `confidence` (`confirmed | suggested | inferred`) and `source` (`human | ai | owner`).** Strict-mode users (`user_profiles.strictness = 'strict'`) only see items where every association is `confirmed`. The honest-disclosure UX depends on these columns being accurate.

The same computation lives in `packages/filter-engine/src/index.ts` (`applyProfile`) so a client can recompute visible/hidden without a roundtrip. **When the Ruby changes, the TS implementation must change with it** — both have tests; both must stay green. `TasteScoring` has its own TS mirror (`taste.ts`) sharing the `taste-parity.json` fixture.

Taxonomy (`ingredients`, `tags`) is hierarchical via Postgres `ltree`. Adding/removing nodes is admin-gated. `aliases[]` is what lets "garbanzo" resolve to "chickpea".

See `docs/schema.md` for the 60-second tour of all ~30 tables, and `docs/ingestion.md` for how the AI pipeline writes into them.

## Cross-package contracts

- **API types are generated, not hand-written.** The chain: rswag specs in `apps/api/spec/integration/` → `bin/openapi-export` writes `docs/openapi.json` → `pnpm --filter @biteworthy/api-types build:codegen` writes `src/generated.ts`. When you add or change an endpoint, write/update its rswag spec and re-run both steps in the same PR — CI (`codegen:check` in `ci-js.yml`) fails if `generated.ts` drifts from the checked-in spec. A few hand-written read-model types (Ingredient, Tag, Restaurant, Item) remain in `packages/api-types/src/index.ts` until their endpoints get rswag specs.
- `@biteworthy/filter-engine` consumes `@biteworthy/api-types`. If you change the shape of an `Item`, fix both.
- `@biteworthy/ui-tokens` is consumed by `apps/web/tailwind.config.ts` (as Tailwind theme extensions) and `apps/mobile` (mapped into `StyleSheet.create`). Token renames touch all three.

## Conventions specific to this repo

- **Code style is enforced by `.prettierrc` at the repo root**: semicolons ON, single quotes, trailing commas, 100-col, 2-space. This **overrides** any conflicting global preference (e.g. `~/CLAUDE.md` says no semis / double quotes — that does not apply here; this repo uses semis + single quotes).
- TypeScript everywhere uses `tsconfig.base.json` (`strict`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `moduleResolution: bundler`).
- Conventional commits are required by `pr-title.yml` workflow: `feat(api): …`, `fix(web): …`, `docs: …`, `chore(ci): …`.
- Branch naming for delivery-loop work: `claude/<phase-slug>` (e.g. `claude/phase-1.2-omniauth`).
- **`.github/workflows/auto-merge.yml` enables squash auto-merge on every non-draft PR**, so a PR merges itself the moment required checks go green. The `claude-cd` / `auto-merge-ok` label gate was dropped 2026-04-29 and the labels are now tagging only — withholding them does **not** hold a PR back. Two consequences worth internalizing: review a change *before* opening the PR, because afterwards there may be no window; and open a draft if you need one to stay put. `docs/delivery-playbook.md` §"Auto-merge policy" is the authority (its earlier sections still describe the pre-2026-04-29 gate).
- `master` is the default branch (not `main`).
- **Never edit a previously-shipped migration.** Add a new one. The auto-merge policy in `docs/delivery-playbook.md` blocks destructive edits under `apps/api/db/migrate/`.
- **Never modify anything under `_legacy/`.** It's frozen reference material.

## Where to look first

- `docs/roadmap.md` — phase plan + the **Next up** queue (the autonomous delivery loop reads this top-down).
- `docs/delivery-playbook.md` — the source-of-truth procedure for the `/loop 30m` autonomous loop. If you're picking up loop work, read this first.
- `docs/plans/` — per-task acceptance criteria for live work; completed phase subplans are archived under `docs/plans/archive/` (read-only).
- `docs/status.md` — running log, newest first; what the previous tick left mid-flight.
- `docs/schema.md` — the data model in 60 seconds.
- `docs/mcp.md` — the tool layer (`app/services/tools/`) and the `/mcp` endpoint. Read this before adding a capability: new domain operations go in as tools, and REST controllers adapt to them.
- `docs/ingestion.md` — how Claude vision + prompt-cached taxonomy turns a menu photo into staged `IngestionItem`s.
- `docs/analytics.md` — the funnel-event contract behind `packages/analytics`.
- `docs/launch-readiness.md` — the human-action launch checklist (provisioning, store accounts, deploy).
- `docs/adr/` — why every pick is what it is (0001 stack, 0007 hosting = Kamal + Hetzner + Neon, 0006 analytics = PostHog, plus email/blob/web-hosting). Read the relevant ADR before proposing alternatives.

## CI

Two workflows gate PRs:

- `ci-js.yml` — runs on changes to `apps/web/`, `apps/mobile/`, `packages/`, `docs/openapi.json`, or root config. Steps: `pnpm typecheck` → `pnpm lint` → `pnpm test` → api-types codegen drift check.
- `ci-api.yml` — runs on changes to `apps/api/`. Boots Postgres 16 + ImageMagick (dish-photo cropping shells out to it), then `bin/rails db:create db:schema:load`, then `bin/rspec`. **Brakeman runs in the same job and blocks** (no `continue-on-error`); **Rubocop** runs with `continue-on-error: true` (informational only).

Both are required for auto-merge. Don't request human review on red.

Other workflows run but don't gate auto-merge: `migration-guard.yml` (blocks edits to previously-shipped migrations under `apps/api/db/migrate/`), `ci-nightly.yml` (nightly full suite), `codeql.yml` (security scan), `expo-align.yml` (mobile Expo-SDK dependency alignment), `labeler.yml` (auto-labels PRs, feeds the auto-merge opt-in), `pr-title.yml` (conventional-commit title check), `auto-merge.yml` (the merge driver), `deploy-api.yml` (runs `kamal deploy` to Hetzner on merge to master touching `apps/api/**`, or on manual `workflow_dispatch`; needs the `KAMAL_SECRETS_B64`, `SSH_PRIVATE_KEY`, and `SSH_KNOWN_HOSTS` repo secrets — the last pins the box's host keys, so re-pin it only after confirming a genuine rebuild, never to clear a host-key error).
