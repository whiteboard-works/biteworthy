# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Stack at a glance

Pnpm + Turborepo monorepo. Three apps + four shared packages:

- `apps/api` — Rails 8 (Ruby 3.3.6) JSON API on Postgres 16. **Not** part of the pnpm workspace; lives as its own Bundler tree.
- `apps/web` — Next.js 15 App Router + Tailwind. Dev port `:3001`.
- `apps/mobile` — Expo SDK 52 + expo-router.
- `packages/api-types` — TS types (currently hand-written; OpenAPI codegen lands in Phase 1.6).
- `packages/filter-engine` — pure-TS dietary filter, shared by web + mobile, with Vitest tests. Mirrors the server-side SQL.
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

The API has its own toolchain — run from `apps/api/`:

```bash
bundle install
bin/rails db:create db:schema:load db:seed
bin/rails s -p 3000                     # API on :3000 (web is on :3001)
bin/jobs                                # Solid Queue worker (or boot inline: SOLID_QUEUE_IN_PUMA=true bin/rails s)
bundle exec rspec                       # full test suite
bundle exec rspec spec/requests/foo_spec.rb     # one file
bundle exec rspec spec/requests/foo_spec.rb:42  # one example by line
bundle exec rubocop --parallel
bundle exec brakeman --no-pager --quiet --format plain
```

Per-app test runners (use these for narrow runs instead of `pnpm test`):

```bash
pnpm --filter @biteworthy/filter-engine test
pnpm --filter @biteworthy/web test
pnpm --filter @biteworthy/mobile test
```

Postgres needs the `ltree`, `pg_trgm`, `pgcrypto`, and `citext` extensions — the migrations enable them, but the role needs `CREATE EXTENSION` the first time.

## Architecture: the filter is the product

The schema is shaped around one query: "given a user's avoid lists, return the items at this restaurant they can eat." That query is

```sql
SELECT items.*
FROM items
WHERE items.restaurant_id = $1
  AND items.status = 'published'
  AND NOT (items.ingredient_ids && $avoid_ingredients_uuid_array)
  AND NOT (items.tag_ids        && $avoid_tags_uuid_array)
  AND ($strictness <> 'strict' OR items.confidence = 'confirmed')
ORDER BY cardinality(items.tag_ids & $prefer_tags_uuid_array) DESC,
         items.popularity DESC;
```

Two consequences of this shape that affect almost every change in `app/models/item*.rb`:

1. **Items carry denormalized `ingredient_ids uuid[]` and `tag_ids uuid[]`** with GIN indexes. The `ItemIngredient` and `ItemTag` join tables are the source of truth + audit log; `after_save`/`after_destroy` callbacks on the joins keep the arrays in sync. **Never write to the arrays directly** — write to the joins.
2. **Every join row has `confidence` (`confirmed | suggested | inferred`) and `source` (`human | ai | owner`).** Strict-mode users (`user_profiles.strictness = 'strict'`) only see items where every association is `confirmed`. The "honest disclosure" UX (hidden items always show *why*) depends on these columns being accurate.

The same filter lives in `packages/filter-engine/src/index.ts` for the client. **When the SQL changes, the TS implementation must change with it** — both have tests; both must stay green.

Taxonomy (`ingredients`, `tags`) is hierarchical via Postgres `ltree`. Adding/removing nodes is admin-gated. `aliases[]` is what lets "garbanzo" resolve to "chickpea".

See `docs/schema.md` for the 60-second tour of all 25-ish tables, and `docs/ingestion.md` for how the AI pipeline writes into them.

## Cross-package contracts

- The Rails OpenAPI spec → `packages/api-types/src/generated.ts` codegen pipeline is **not yet wired up** (Phase 1.6). For now, `packages/api-types/src/index.ts` is hand-written. When you add an endpoint, update the hand-written types in the same PR. Once 1.6 lands, the hand-written file is deleted and only `generated.ts` is re-exported.
- `@biteworthy/filter-engine` consumes `@biteworthy/api-types`. If you change the shape of an `Item`, fix both.
- `@biteworthy/ui-tokens` is consumed by `apps/web/tailwind.config.ts` (as Tailwind theme extensions) and `apps/mobile` (mapped into `StyleSheet.create`). Token renames touch all three.

## Conventions specific to this repo

- **Code style is enforced by `.prettierrc` at the repo root**: semicolons ON, single quotes, trailing commas, 100-col, 2-space. This **overrides** any conflicting global preference (e.g. `~/CLAUDE.md` says no semis / double quotes — that does not apply here; this repo uses semis + single quotes).
- TypeScript everywhere uses `tsconfig.base.json` (`strict`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `moduleResolution: bundler`).
- Conventional commits are required by `pr-title.yml` workflow: `feat(api): …`, `fix(web): …`, `docs: …`, `chore(ci): …`.
- Branch naming for delivery-loop work: `claude/<phase-slug>` (e.g. `claude/phase-1.2-omniauth`). The `claude-cd` label + the `auto-merge-ok` label together opt a PR into `.github/workflows/auto-merge.yml`.
- `master` is the default branch (not `main`).
- **Never edit a previously-shipped migration.** Add a new one. The auto-merge policy in `docs/delivery-playbook.md` blocks destructive edits under `apps/api/db/migrate/`.
- **Never modify anything under `_legacy/`.** It's frozen reference material.

## Where to look first

- `docs/roadmap.md` — phase plan + the **Next up** queue (the autonomous delivery loop reads this top-down).
- `docs/delivery-playbook.md` — the source-of-truth procedure for the `/loop 30m` autonomous loop. If you're picking up loop work, read this first.
- `docs/plans/phase-N.md` — per-task acceptance criteria for the current phase.
- `docs/status.md` — running log, newest first; what the previous tick left mid-flight.
- `docs/schema.md` — the data model in 60 seconds.
- `docs/ingestion.md` — how Claude vision + prompt-cached taxonomy turns a menu photo into staged `IngestionItem`s.
- `docs/adr/0001-stack.md` — why every stack pick is what it is. Read before proposing alternatives.

## CI

Two workflows gate PRs:

- `ci-js.yml` — runs on changes to `apps/web/`, `apps/mobile/`, `packages/`, or root config. Steps: `pnpm typecheck` → `pnpm lint` → `pnpm test`.
- `ci-api.yml` — runs on changes to `apps/api/`. Boots Postgres 16, then `bin/rails db:create db:schema:load`, then `bin/rspec`. Brakeman + Rubocop run with `continue-on-error: true` (informational, not blocking).

Both are required for auto-merge. Don't request human review on red.
