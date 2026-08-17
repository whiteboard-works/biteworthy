# AGENTS.md

<!-- BEGIN codex-review-guidelines (managed by AGENTS-REVIEW-ROLLOUT.md) -->
## Review guidelines

**Context:** BiteWorthy is a dietary-filter app — users set avoid lists and are shown only menu items safe for them — shipped as a monorepo: a Rails API (`apps/api`), a Next.js web app (`apps/web`), an Expo mobile app (`apps/mobile`), and shared TypeScript packages under `packages/` (`filter-engine`, `analytics`, `api-types`, `ui-tokens`, `eslint-config`, `version-history`). The safe/unsafe decision is made in exactly one place — `Menus::Filter#reasons_for` in the Rails API — and both clients render the `status` / `reasons` they receive. `packages/filter-engine` holds shared *presentation* helpers and wire types only, despite the name; there is no client-side filter. **The worst failure is an unsafe item shown as safe to an allergic user.** Legal remediation E1–E13 (GDPR/CCPA, allergen disclosure) is baked into the schema and the analytics contract. (This is the repo-root block covering cross-package contracts; see the nested `apps/*/AGENTS.md` for per-stack rules.)

GitHub surfaces only P0/P1 findings, so phrase issues as block-worthy and escalate anything lower you still want caught. CI already runs JS typecheck/lint/test (`pnpm`, `ci-js`), the api-types codegen-drift check (`codegen:check`), the Rails RSpec suite + Brakeman (`ci-api`), the migration guard, Expo SDK alignment, and conventional PR-title lint — don't restate those. **RuboCop runs but is `continue-on-error` (informational) — do not raise blocking findings for RuboCop/style.**

Block a PR (P0/P1) when it:

- **Adds a second implementation of the filter.** `Menus::Filter#reasons_for` is the only place an item becomes visible or hidden, and any other consumer of an avoid list must route through `Menus::Filter.resolve_subtrees` so a parent node still hides its descendants (`Cities::RestaurantRanking`, which counts the same dishes in SQL for the SEO pages, is the one other consumer). Reject a new copy of the rule — in TypeScript or in SQL — unless it comes with a shared fixture generated from `Menus::Query#serialize` that both suites assert against. A copy checked only against expectations written in its own language proves nothing; the repo shipped exactly that for months.
- **Writes `items.ingredient_ids` or `items.tag_ids` directly.** These columns are denormalized by `ItemIngredient#sync_item_ingredient_ids` / `ItemTag#sync_item_tag_ids` (`update_columns` on save/destroy). A direct write corrupts the array index and can make an unsafe item match as safe.
- **Renames or removes a `packages/analytics` event or field.** The names in `EVENTS` and their property shapes are a dashboard contract. In particular `profile_set` must not re-acquire the health fields removed for legal E7 (`preset_slug`, `strictness`, avoid-list counts). Adding optional fields is fine; renames need a coordinated dashboard change.
- **Changes an API endpoint without regenerating types.** A new/changed endpoint must regenerate `docs/openapi.json` and `@biteworthy/api-types` in the same PR. `codegen:check` gates drift, but only for endpoints that have rswag specs — so also confirm the endpoint has one (see `apps/api/AGENTS.md`).
- **Edits anything under `_legacy/`.** It is frozen reference material; any change — even a comment — is wrong.
- **Modifies an already-shipped migration** under `apps/api/db/migrate/`. The migration guard blocks it, but flag the intent first — add a new migration instead.

Also treat these normally-lower-severity issues as P1 so they surface:

- Enabling auto-merge while a second commit is still outstanding — the squash has silently dropped commits before (push, wait for CI on the full SHA, then merge).
- A change to the `UserProfile` `strictness` enum / `STRICTNESS` constant without updating the corresponding TS type in `@biteworthy/api-types` (codegen catches shape drift, not enum-value additions).

For architecture and conventions, also follow CLAUDE.md and the nested `apps/api`, `apps/web`, and `apps/mobile` `AGENTS.md` files.
<!-- END codex-review-guidelines -->
