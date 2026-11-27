# AGENTS.md

Rules for every coding agent in this repository. This file is always loaded; open a file under _Read when needed_ when its trigger matches your task.

## What this is

BiteWorthy ("scan any menu, see only what you can eat"): a pnpm 10 + Turborepo monorepo on Node 22. `apps/api` is Rails 8.1 on Ruby 3.3.6 and Postgres 16, its own Bundler tree outside the pnpm workspace; `apps/web` is Next.js 16 (port 3001, Vercel); `apps/mobile` is Expo SDK 56 (EAS); `packages/` holds `api-types`, `filter-engine`, `analytics`, `ui-tokens`, `eslint-config`, and `version-history`. `_legacy/` is the frozen 2020 Rails 4.2 app.

## Commands

`ci-js.yml` builds `@biteworthy/web` (typed routes), then runs the root scripts; `ci-api.yml` runs `bin/rspec`, Brakeman, and RuboCop from `apps/api/` on `ubuntu-24.04` (Ruby 3.3.6 is not prebuilt on `ubuntu-latest` / 26.04), all blocking.

```bash
pnpm install && pnpm dev                   # web :3001 + mobile
pnpm typecheck && pnpm lint && pnpm test   # Vitest (web, packages), Jest (mobile)
pnpm --filter @biteworthy/api-types codegen:check
pnpm --filter @biteworthy/web test         # one package (`pnpm web …` / `pnpm mobile …` are aliases)
pnpm bump --note "…"                       # calver release entry in packages/version-history
docker compose up                          # API :3000 + Solid Queue worker + Postgres
# from apps/api/:
bundle exec rspec spec/requests/foo_spec.rb:42
bundle exec rubocop --parallel && bundle exec brakeman --no-pager --quiet --format plain
bin/openapi-export                         # docs/openapi.json from the rswag specs
```

Inside the container, test commands need `docker compose exec -e RAILS_ENV=test api …` (it bakes `RAILS_ENV=development`).

## Hard rules

- **pnpm only, never `npm`.** The API uses Bundler.
- **Prettier here is semicolons on, single quotes**, 100 columns (`.prettierrc`), overriding any global preference. Never reformat to another style.
- **Never edit anything under `_legacy/`**, not even a comment.
- **Never edit, delete, or rename a shipped migration** in `apps/api/db/migrate/`; add a new one.
- **Every non-draft PR squash-merges itself once the required checks are green** (`typecheck · lint · test`, `rspec · brakeman · rubocop`, `javascript-typescript`, `ruby`, and `codex-gate` from `auto-merge.yml`). `codex-gate` is success only after Codex has reviewed the current head with no unresolved P0/P1 threads (Dependabot patch/minor skip that wait). Mark `codex-gate` required in Settings → Branches → master. No label or required GitHub approval holds it; open a draft to hold a PR.
- **A merge to `master` touching any file under `apps/api/`, Markdown included, deploys the API to production** (`deploy-api.yml`, Kamal). Re-pin the `SSH_KNOWN_HOSTS` secret only after confirming a real rebuild of the box, never to clear a host-key error.
- **The server's filter is the only filter.** `Menus::Filter#reasons_for` alone decides an item's `status` / `reasons`; web and mobile render them and never derive visible or hidden.
- **Never write `items.ingredient_ids` / `items.tag_ids` directly**; write the `ItemIngredient` / `ItemTag` join rows. Read them via `item.denormalized_ingredient_ids` / `denormalized_tag_ids` (the plain reader costs a query per item).
- **A new or changed endpoint ships with its rswag spec, `bin/openapi-export`, and `api-types` `build:codegen` in the same PR.** The hand-written `Confidence` / `Strictness` types in `packages/api-types/src/index.ts` change with their Rails enums; `codegen:check` cannot see them.
- **Never rename or remove a `packages/analytics` event or property**; add only.
- **Branch off `master` (not `main`); PR titles are conventional commits** (`pr-title.yml`).
- **Never add to `apps/api/.rubocop_todo.yml`**; new Ruby code passes RuboCop.
- **Keep the tracking docs true in the same PR**: tick `docs/roadmap.md`, add a `docs/status.md` line for anything non-trivial, fix doc facts the change made stale.

## Read when needed

| File | Read this before… |
| ---- | ----------------- |
| `agent-docs/working-rules.md` | any change bigger than a one-line fix: planning, scope, tests, reporting. |
| `agent-docs/architecture.md` | touching `app/models/item*.rb`, `Menus::*`, `TasteScoring`, `Cities::RestaurantRanking`, join tables, or a package used by more than one app. |
| `apps/api/AGENTS.md` | changing `apps/api`: allergen and consent columns, join-row confidence, VCR cassettes, mailers. |
| `apps/web/AGENTS.md` | changing `apps/web`, or an env var that could reach the browser. |
| `apps/mobile/AGENTS.md` | changing `apps/mobile` or an Expo-managed dependency. |
| `.github/README.md` | editing a workflow, a required check, or a deploy secret. |
| `docs/delivery-playbook.md` | running the delivery loop or working a `claude/*` branch. |
| `docs/local-dev.md` | running the API natively, resetting the database, or editing `apps/api/.env`. |
| `docs/schema.md` | adding a table or column. |
| `docs/mcp.md` | adding a capability (new operations are tools in `apps/api/app/services/tools/`). |
| `docs/ingestion.md` | changing the menu import pipeline or its model calls. |
| `docs/analytics.md` | adding or changing an analytics event. |
| `docs/adr/` | proposing a different host, provider, or vendor. |
| `docs/roadmap.md` (and its plans in `docs/plans/`), `docs/status.md`, `docs/launch-readiness.md` | choosing work, resuming someone's work, or touching launch provisioning. |

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

## Ask vs. proceed

Proceed without asking on roadmap items, bug fixes, tests, and doc corrections. Stop and ask the owner (a top-level PR comment starting `@shadoath`, per `docs/delivery-playbook.md`) when:

- the same CI failure has repeated three times;
- a review thread asks a question or needs a judgment call;
- the work needs a secret or account agents do not have (Apple signing, production keys), or is a human step in `docs/launch-readiness.md`;
- a roadmap item is marked `[BLOCKED]`;
- one PR's diff passes 2,000 lines without a clear reason;
- a command would run against production (`RAILS_ENV=production`, a production `DATABASE_URL`, or a manual deploy dispatch).

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
