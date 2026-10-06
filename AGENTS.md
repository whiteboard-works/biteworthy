# AGENTS.md

Guidance for coding agents (Claude Code, Codex, and any other CLI) working in this repository.
The review-guidelines block at the end is the Codex reviewer contract; everything above it applies to every agent.

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

Pnpm + Turborepo monorepo. Three apps + six shared packages:

- `apps/api` — Rails 8 (Ruby 3.3.6) JSON API on Postgres 16. **Not** part of the pnpm workspace; lives as its own Bundler tree.
- `apps/web` — Next.js 16 App Router + Tailwind. Dev port `:3001`.
- `apps/mobile` — Expo SDK 56 + expo-router.
- `packages/api-types` — TS types codegen'd from `docs/openapi.json` (see Cross-package contracts below).
- `packages/filter-engine` — the menu wire types plus the presentation helpers web + mobile share (reason chips, section grouping, "show anyway" overrides, Top Picks selection, share-token encoding), with Vitest tests. **It does not filter** — despite the name, no client decides visible/hidden.
- `packages/analytics` — the funnel-event taxonomy (`EVENTS` map + `EventPropsMap`; 18 events: 9 core funnel/engagement, 3 auth, 3 chat, 3 scan). Event names/payloads are a contract with the launch dashboards — **renaming an event breaks downstream funnels**; add new events + optional fields freely. `docs/analytics.md` documents each event; when doc and types disagree, the types win.
- `packages/ui-tokens` — design tokens consumed by Tailwind (web) and `StyleSheet.create` (mobile).
- `packages/eslint-config` — minimal flat config; framework rules live per-app.
- `packages/version-history` — the calver release log (`YYYY.M.D[.X]`): `src/history.json` is the source of truth, `pnpm bump --note "…"` prepends a release, a contract test rejects malformed edits, and web (`/updates` + footer) and mobile (home screen) render its exports.

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
pnpm test                  # turbo test (Vitest for web + packages, Jest for mobile)

pnpm api <script>          # alias for: pnpm --filter @biteworthy/api ... (no JS scripts yet — use bin/rails)
pnpm web <script>          # alias for: pnpm --filter @biteworthy/web ...
pnpm mobile <script>       # alias for: pnpm --filter @biteworthy/mobile ...

pnpm bump [--note "…"]     # prepend a calver release (YYYY.M.D[.X]) to packages/version-history
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
`docker compose exec api …` — but test-env commands need the env override
(`docker compose exec -e RAILS_ENV=test api bundle exec rspec`), because the
container bakes `RAILS_ENV=development`.

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

Ranking is separate. When the signed-in user has taste signals, `TasteScoring.scores_for` runs one SQL query per restaurant (liked/disliked overlap ± average visible rating) and the response is re-sorted by `taste_score`. Otherwise the order is section position (nulls last), then item position, then name. Nothing sorts by `user_profiles.prefer_tag_ids`, and `items.popularity` is gone — it was read in three places, written by none, and its scoring term was structurally zero.

The array-overlap SQL does exist, just not here — `Cities::RestaurantRanking` uses `NOT (items.ingredient_ids && ARRAY[…]::uuid[])` inside a `COUNT(…) FILTER` to rank a city's restaurants by how many dishes pass a preset, in one query instead of 30 calls to the items endpoint.

Two consequences that affect almost every change in `app/models/item*.rb`:

1. **Items carry denormalized `ingredient_ids uuid[]` and `tag_ids uuid[]`.** The Ruby filter, `TasteScoring`, and `Cities::RestaurantRanking` all read them, which is what keeps a restaurant page to a couple of queries instead of a join per item. The `ItemIngredient` and `ItemTag` join tables are the source of truth + audit log; the `SyncsDenormalizedIds` concern on the joins rebuilds the arrays from the join rows after save/destroy (bulk writers wrap in `Item.defer_denormalization`). **Never write to the arrays directly** — write to the joins. **Reading them has a trap**: `item.ingredient_ids` resolves to the has_many-through reader, which shadows the identically-named column and costs a query per item — use `item.denormalized_ingredient_ids` / `denormalized_tag_ids` unless you actually need the join rows.
2. **Every join row has `confidence` (`confirmed | suggested | inferred`) and `source` (`human | ai | owner`).** Strict-mode users (`user_profiles.strictness = 'strict'`) only see items where every association is `confirmed`. The honest-disclosure UX depends on these columns being accurate.

**There is exactly one filter, and it is the server's.** `Menus::Filter#reasons_for` decides `status` / `reasons`; web and mobile render what they receive and never recompute it. The same goes for ranking — `TasteScoring` emits `taste_score` / `taste_reasons` and the clients only select and phrase (`topPicksFromScores`, `tasteReasonLine`). A hand-mirrored TS copy of both used to live in `packages/filter-engine` with a lockstep rule attached; it was deleted in Aug 2026 because nothing ever called it, and its "parity" test compared TS to TS.

If a client-side re-filter is ever genuinely wanted, the bar is a real shared fixture generated from `Menus::Query#serialize` that both suites assert against — the way `packages/filter-engine/fixtures/taste-parity.json` pins `TasteScoring` today. Note also that a client cannot filter correctly from a stored profile at all: `Menus::Subtree` expands an avoided node to its descendants before any comparison, and a client has no taxonomy to expand with.

Taxonomy (`ingredients`, `tags`) is hierarchical via Postgres `ltree`. Adding/removing nodes is admin-gated. `aliases[]` is what lets "garbanzo" resolve to "chickpea".

See `docs/schema.md` for the 60-second tour of all ~30 tables, and `docs/ingestion.md` for how the AI pipeline writes into them.

## Cross-package contracts

- **API types are generated, not hand-written.** The chain: rswag specs in `apps/api/spec/integration/` → `bin/openapi-export` writes `docs/openapi.json` → `pnpm --filter @biteworthy/api-types build:codegen` writes `src/generated.ts`. When you add or change an endpoint, write/update its rswag spec and re-run both steps in the same PR — CI (`codegen:check` in `ci-js.yml`) fails if `generated.ts` drifts from the checked-in spec. Two hand-written enums remain in `packages/api-types/src/index.ts` — `Confidence` and `Strictness` — because they have no component schema behind them; adding a value to either Rails enum without adding it here is drift `codegen:check` cannot catch.
- `@biteworthy/filter-engine` re-exports those two enums as the canonical filter wire types. Everything else it exposes is its own.
- `@biteworthy/ui-tokens` is consumed by `apps/web/tailwind.config.ts` (as Tailwind theme extensions) and `apps/mobile` (mapped into `StyleSheet.create`). Token renames touch all three.

## Conventions specific to this repo

- **Code style is enforced by `.prettierrc` at the repo root**: semicolons ON, single quotes, trailing commas, 100-col, 2-space. This **overrides** any conflicting global preference (a global agent-instructions file saying no semis / double quotes does not apply here; this repo uses semis + single quotes).
- TypeScript everywhere uses `tsconfig.base.json` (`strict`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `moduleResolution: bundler`).
- Conventional commits are required by `pr-title.yml` workflow: `feat(api): …`, `fix(web): …`, `docs: …`, `chore(ci): …`.
- Branch naming for delivery-loop work: `claude/<phase-slug>` (e.g. `claude/phase-1.2-omniauth`).
- **`.github/workflows/auto-merge.yml` enables squash auto-merge on every non-draft PR**, so a PR merges itself the moment required checks go green. The `claude-cd` / `auto-merge-ok` label gate was dropped 2026-04-29 and the labels are now tagging only — withholding them does **not** hold a PR back. Two consequences worth internalizing: review a change *before* opening the PR, because afterwards there may be no window; and open a draft if you need one to stay put. `docs/delivery-playbook.md` §"Auto-merge policy" is the authority.
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

Two workflows run the test suites:

- `ci-js.yml` — runs on changes to `apps/web/`, `apps/mobile/`, `packages/`, `docs/openapi.json`, or root config. Steps: `pnpm typecheck` → `pnpm lint` → `pnpm test` → api-types codegen drift check.
- `ci-api.yml` — runs on changes to `apps/api/`. Boots Postgres 16 + ImageMagick (dish-photo cropping shells out to it), then `bin/rails db:create db:schema:load`, then `bin/rspec`. **Brakeman and Rubocop run in the same job and both block** (neither has `continue-on-error`). Rubocop inherits Rails' omakase style plus a generated `.rubocop_todo.yml` that freezes the pre-existing offences, so new code has to be clean while the backlog stays grandfathered — run `bundle exec rubocop --parallel` before pushing rather than adding a todo entry.

Branch protection requires four check runs: those two jobs plus the two `codeql.yml` language jobs (`javascript-typescript`, `ruby`). Don't request human review on red.

Other workflows run but don't gate auto-merge: `migration-guard.yml` (blocks edits to previously-shipped migrations under `apps/api/db/migrate/`), `ci-nightly.yml` (nightly full suite), `expo-align.yml` (mobile Expo-SDK dependency alignment), `labeler.yml` (auto-applies `area:*` labels), `pr-title.yml` (conventional-commit title check), `auto-merge.yml` (the merge driver), `deploy-api.yml` (runs `kamal deploy` to Hetzner on merge to master touching `apps/api/**` or the workflow file itself, or on manual `workflow_dispatch`; needs the `KAMAL_SECRETS_B64`, `SSH_PRIVATE_KEY`, and `SSH_KNOWN_HOSTS` repo secrets — the last pins the box's host keys, so re-pin it only after confirming a genuine rebuild, never to clear a host-key error).

<!-- BEGIN codex-review-guidelines (managed by AGENTS-REVIEW-ROLLOUT.md) -->
## Review guidelines

**Context:** BiteWorthy is a dietary-filter app — users set avoid lists and are shown only menu items safe for them — shipped as a monorepo: a Rails API (`apps/api`), a Next.js web app (`apps/web`), an Expo mobile app (`apps/mobile`), and shared TypeScript packages under `packages/` (`filter-engine`, `analytics`, `api-types`, `ui-tokens`, `eslint-config`, `version-history`). The safe/unsafe decision is made in exactly one place — `Menus::Filter#reasons_for` in the Rails API — and both clients render the `status` / `reasons` they receive. `packages/filter-engine` holds shared *presentation* helpers and wire types only, despite the name; there is no client-side filter. **The worst failure is an unsafe item shown as safe to an allergic user.** Legal remediation E1–E13 (GDPR/CCPA, allergen disclosure) is baked into the schema and the analytics contract. (This is the repo-root block covering cross-package contracts; see the nested `apps/*/AGENTS.md` for per-stack rules.)

GitHub surfaces only P0/P1 findings, so phrase issues as block-worthy and escalate anything lower you still want caught. CI already runs JS typecheck/lint/test (`pnpm`, `ci-js`), the api-types codegen-drift check (`codegen:check`), the Rails RSpec suite + Brakeman (`ci-api`), the migration guard, Expo SDK alignment, and conventional PR-title lint — don't restate those. **RuboCop also runs and blocks; don't restate style findings it will catch.**

Block a PR (P0/P1) when it:

- **Adds a second implementation of the filter.** `Menus::Filter#reasons_for` is the only place an item becomes visible or hidden, and any other consumer of an avoid list must route through `Menus::Filter.resolve_subtrees` so a parent node still hides its descendants (`Cities::RestaurantRanking`, which counts the same dishes in SQL for the SEO pages, is the one other consumer). Reject a new copy of the rule — in TypeScript or in SQL — unless it comes with a shared fixture generated from `Menus::Query#serialize` that both suites assert against. A copy checked only against expectations written in its own language proves nothing; the repo shipped exactly that for months.
- **Writes `items.ingredient_ids` or `items.tag_ids` directly.** These columns are denormalized by the `SyncsDenormalizedIds` concern (`sync_denormalized_ids` after save/destroy on the join rows). A direct write corrupts the array index and can make an unsafe item match as safe.
- **Renames or removes a `packages/analytics` event or field.** The names in `EVENTS` and their property shapes are a dashboard contract. In particular `profile_set` must not re-acquire the health fields removed for legal E7 (`preset_slug`, `strictness`, avoid-list counts). Adding optional fields is fine; renames need a coordinated dashboard change.
- **Changes an API endpoint without regenerating types.** A new/changed endpoint must regenerate `docs/openapi.json` and `@biteworthy/api-types` in the same PR. `codegen:check` gates drift, but only for endpoints that have rswag specs — so also confirm the endpoint has one (see `apps/api/AGENTS.md`).
- **Edits anything under `_legacy/`.** It is frozen reference material; any change — even a comment — is wrong.
- **Modifies an already-shipped migration** under `apps/api/db/migrate/`. The migration guard blocks it, but flag the intent first — add a new migration instead.

Also treat these normally-lower-severity issues as P1 so they surface:

- Enabling auto-merge while a second commit is still outstanding — the squash has silently dropped commits before (push, wait for CI on the full SHA, then merge).
- A change to the `UserProfile` `strictness` enum / `STRICTNESS` constant without updating the corresponding TS type in `@biteworthy/api-types` (codegen catches shape drift, not enum-value additions).

For architecture and conventions, also follow the sections above and the nested `apps/api`, `apps/web`, and `apps/mobile` `AGENTS.md` files.
<!-- END codex-review-guidelines -->

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
