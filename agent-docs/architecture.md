# Architecture: the filter is the product

Read before touching `apps/api/app/models/item*.rb`, `Menus::*`, `TasteScoring`, `Cities::RestaurantRanking`, the `ItemIngredient` / `ItemTag` join tables, or a shared package. The invariants themselves are in the root `AGENTS.md`; this file is the why.

## Apps and packages

- `apps/api`: Rails 8.1 (Ruby 3.3.6) JSON API on Postgres 16. Not in the pnpm workspace (`pnpm-workspace.yaml` lists `apps/web`, `apps/mobile`, `packages/*`), and it has no `package.json`. Postgres needs the `ltree`, `pg_trgm`, `pgcrypto`, and `citext` extensions; the first migration enables them, so the role needs `CREATE EXTENSION` the first time.
- `apps/web`: Next.js 16 App Router + Tailwind 3. Dev port 3001.
- `apps/mobile`: Expo SDK 56 + expo-router.
- `packages/api-types`: TypeScript types generated from `docs/openapi.json`.
- `packages/filter-engine`: the menu wire types plus the presentation helpers web and mobile share (reason chips, section grouping, "show anyway" overrides, Top Picks selection, share-token encoding), with Vitest tests. Despite the name it does not filter.
- `packages/analytics`: the funnel-event taxonomy (`EVENTS` map + `EventPropsMap`; 18 events: 9 core funnel and engagement, 3 auth, 3 chat, 3 scan). `docs/analytics.md` documents each event; when doc and types disagree, the types win.
- `packages/ui-tokens`: design tokens consumed by Tailwind (web) and `StyleSheet.create` (mobile).
- `packages/eslint-config`: a minimal flat config; framework rules live per app.
- `packages/version-history`: the calver release log (`YYYY.M.D[.X]`). `src/history.json` is the source of truth, `pnpm bump --note "…"` prepends a release, a contract test rejects malformed edits, and web (`/updates` and the footer) and mobile (the home screen) render its exports.

TypeScript everywhere extends `tsconfig.base.json` (`strict`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `moduleResolution: Bundler`).

## The filter never removes rows

The schema is shaped around one question: given a user's avoid lists, which items at this restaurant can they eat, and why not for the rest?

The filter does not run in SQL. `Api::V1::ItemsController#index` hands off to `Menus::Query`, which loads every published item at the restaurant and asks `Menus::Filter#reasons_for` for a per-item `reasons[]` computed in Ruby (array intersection against the avoid lists, plus the strict-mode check). The `get_menu` MCP tool goes through the same two classes, so both answer identically. Items with a non-empty `reasons[]` come back as `status: "hidden"` with the reasons attached. That is the honest-disclosure contract: a hidden item must always be able to say why it's hidden, so it has to survive the query.

Ranking is separate. When the signed-in user has taste signals, `TasteScoring.scores_for` runs one SQL query per restaurant (liked/disliked overlap plus or minus the average visible rating) and the response is re-sorted by `taste_score`. Otherwise the order is section position (nulls last), then item position, then name. Nothing sorts by `user_profiles.prefer_tag_ids`, and `items.popularity` is gone.

The array-overlap SQL exists in one other place: `Cities::RestaurantRanking` counts, inside a `COUNT(…) FILTER`, how many of a city's dishes pass a preset, in one query instead of one items call per restaurant. Any consumer of an avoid list routes through `Menus::Filter.resolve_subtrees`, because `Menus::Subtree` expands an avoided node to its descendants before any comparison.

## Two consequences for `app/models/item*.rb`

1. **Items carry denormalized `ingredient_ids uuid[]` and `tag_ids uuid[]`.** The Ruby filter, `TasteScoring`, and `Cities::RestaurantRanking` all read them, which keeps a restaurant page to a couple of queries. The `ItemIngredient` and `ItemTag` join tables are the source of truth and audit log; the `SyncsDenormalizedIds` concern rebuilds the arrays from the join rows after save and destroy, and bulk writers wrap their work in `Item.defer_denormalization`. `item.ingredient_ids` resolves to the has-many-through reader, which shadows the column and costs a query per item, so read `item.denormalized_ingredient_ids` / `denormalized_tag_ids` unless you need the join rows.
2. **Every join row has `confidence` (`confirmed | suggested | inferred`) and `source`** (`human | ai | owner | match | derived | ingredient_derived`, `ItemIngredient::SOURCES` / `ItemTag::SOURCES`). The item also has its own `items.confidence`, and that is what strict mode reads: with `strictness == "strict"`, `Menus::Filter#reasons_for` hides any item whose `items.confidence` is not `confirmed`. When an import creates a dish, `IngestionItem#promote!` sets it to the weakest ingredient row's confidence (tags do not count; no ingredients means `suggested`); when a re-scan updates a dish, `derive_item_confidence!` only ever lowers it, never raises it. The honest-disclosure UX depends on all of these being accurate.

## One filter, and it is the server's

`Menus::Filter#reasons_for` decides `status` / `reasons`; web and mobile render what they receive. Ranking works the same way: `TasteScoring` emits `taste_score` / `taste_reasons`, and the clients only select and phrase (`topPicksFromScores`, `tasteReasonLine` in `packages/filter-engine/src/taste.ts`). A hand-mirrored TypeScript copy of both used to live in `packages/filter-engine`; it was deleted in August 2026 because nothing called it, and its "parity" test compared TypeScript to TypeScript.

If a client-side re-filter is ever genuinely wanted, the bar is a shared fixture generated from `Menus::Query#serialize` that both suites assert against, the way `packages/filter-engine/fixtures/taste-parity.json` pins `TasteScoring` (asserted in `apps/api/spec/services/taste_scoring_spec.rb`). A client also cannot filter correctly from a stored profile: it has no taxonomy to expand an avoided node with.

The taxonomy (`ingredients`, `tags`) is hierarchical via Postgres `ltree`. Adding or removing nodes is admin-gated. `aliases[]` is what lets "garbanzo" resolve to "chickpea". `docs/schema.md` tours the tables and `docs/ingestion.md` covers how the import pipeline writes into them.

## Cross-package contracts

- **API types are generated.** rswag specs in `apps/api/spec/integration/` → `bin/openapi-export` writes `docs/openapi.json` → `pnpm --filter @biteworthy/api-types build:codegen` writes `src/generated.ts`. `codegen:check` in `ci-js.yml` fails if `generated.ts` drifts from the checked-in spec, but only endpoints with an rswag spec are covered. `Confidence` and `Strictness` stay hand-written in `packages/api-types/src/index.ts` because no component schema backs them.
- `@biteworthy/filter-engine` re-exports those two types as the canonical filter wire types; everything else it exposes is its own.
- `@biteworthy/ui-tokens` is consumed by `apps/web/tailwind.config.ts` (as theme extensions) and by `apps/mobile` screens (in `StyleSheet.create`). A token rename touches the package and both apps.
