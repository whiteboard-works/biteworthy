# Phase 1 — Schema + auth + admin (subplan)

Phase 1 stands up authenticated user accounts, the admin tooling that
lets us hand-build seed data, and the read endpoints + OpenAPI codegen
that the web and mobile apps need before Phase 2 ingestion or Phase 3
filtering can do anything visible.

**Demo at the end:** an admin creates a restaurant + a 10-item menu
in the admin UI; mobile and web both render it; toggling a dietary
profile changes what's shown.

## Tasks (one PR each)

### 1.1 — Devise JWT login + signup endpoints

**Branch**: `claude/phase-1.1-devise-jwt`

- `POST   /api/v1/auth/signup`     → create User + empty UserProfile
- `POST   /api/v1/auth/login`      → returns JWT
- `DELETE /api/v1/auth/logout`     → rotates `users.jti`
- `POST   /api/v1/auth/refresh`    → mints fresh JWT, rotates jti

Implementation notes:
- `devise-jwt` already in the Gemfile. Configure the `jwt_secret_key`
  initializer (use `Rails.application.secret_key_base`).
- JWT denylist strategy: `JtiMatcher` against `users.jti` column —
  a logout rotates the column, invalidating the token.
- ApplicationController enforces JWT presence with a
  `current_user!` helper for namespaced controllers.

Specs:
- request specs covering signup happy + duplicate email + invalid
  email; login happy + wrong password + unconfirmed account; logout
  rotates jti; refresh works once before logout.

Acceptance:
- All four endpoints return JSON, status codes match the spec
  (201/200/204/200).
- `User.first_or_create!(email: ...)` from Rails console works
  end-to-end.

### 1.2 — OmniAuth Apple + Google

**Branch**: `claude/phase-1.2-omniauth`

- `GET /api/v1/auth/:provider`           → OmniAuth init
- `GET /api/v1/auth/:provider/callback`  → finalize, return JWT

Implementation notes:
- Provider configs use ENV vars; document them in `apps/api/.env.example`.
- On first sign-in: create User + empty UserProfile, mark `confirmed_at`.
- On subsequent sign-ins: match by `provider`+`uid`.

Stop conditions:
- Apple signing key not in CI yet → skip CI assertions for that
  provider; integration-tested via VCR cassettes.

### 1.3 — `GET/PATCH /api/v1/profile`

**Branch**: `claude/phase-1.3-user-profile`

- GET returns `{ avoid_ingredient_ids, avoid_tag_ids, prefer_tag_ids,
  strictness, primary_dietary_profile }`.
- PATCH replaces arrays wholesale.
- Optional body field `dietary_profile_slug`: applies a preset's
  ingredient + tag avoid lists to the user (additive, never
  destructive).

Specs: round-trip on each field, dietary-profile preset application.

### 1.4 — Full ingredient port

**Branch**: `claude/phase-1.4-ingredients-port`

- Parse `_legacy/db/seeds/0_ingredients.rb` into structured
  `apps/api/db/seeds/ingredients.yml`.
- Goal: ≥ 1000 ingredients seeded with `path` ltree paths and
  `aliases[]`.
- Categorize by 2020 module groupings (fruits, herbs, grains, nuts,
  legumes, vegetables, animal-products, dairy, meat, poultry, fish,
  spices) → ltree path roots.
- Add `allergen: true` to the big-9 sub-trees.

Specs: seed task is idempotent; spot-check 10 ingredients have
expected ancestry.

### 1.5 — Rails admin dashboard skeleton

**Branch**: `claude/phase-1.5-admin`

- Mount Avo or ActiveAdmin at `/admin`.
- CRUD on: City, Restaurant, Address, Hours, Menu, MenuSection, Item,
  ItemVariant, ItemModifier, Ingredient, Tag, DietaryProfile.
- Read-only on User and Suggestion.
- Behind a `User#is_admin?` flag.

Stop conditions:
- Decision needed on Avo vs ActiveAdmin → ping owner if not already
  decided in the PR description.

### 1.6 — OpenAPI codegen

**Branch**: `claude/phase-1.6-openapi`

- rswag specs for every endpoint shipped in 1.1–1.5.
- `bin/openapi-export` rake task that writes `docs/openapi.json`.
- `pnpm --filter @biteworthy/api-types build:codegen` runs
  `openapi-typescript` → `packages/api-types/src/generated.ts`.
- Hand-written types in `packages/api-types/src/index.ts` deleted;
  re-export only from `generated.ts`.
- CI step that re-runs codegen and fails if the diff is non-empty
  (catches stale types).

### 1.7 — Restaurant + Item read endpoints with filter

**Branch**: `claude/phase-1.7-read-with-filter`

- `GET /api/v1/restaurants/:id/items?profile=…`
- Server runs the dietary-filter SQL described in `docs/schema.md`
  (the `&&` and `cardinality` query).
- Each hidden item carries `reasons: [{kind, ingredient_id|tag_id}]`
  for the transparency UI.
- Strict mode is honored when `profile.strictness == 'strict'`.

Specs: with no profile, all published items show. With "Vegan"
profile, dairy items are hidden with reason. With strict + suggested
items, those are hidden with reason `unconfirmed-strict`.

## Cross-cutting

- **CI subtask** (resolve before 1.7 merges): generate `schema.rb`
  via `bin/rails db:migrate && bin/rails db:schema:dump`, check it
  in, fix the eslint flat-config import order so `pnpm lint` is green.
- **Docs**: each PR updates `docs/openapi.json` (after 1.6 lands) and
  the relevant section of `docs/schema.md` if the model changed.

## Out of scope for Phase 1

- AI ingestion pipeline (Phase 2).
- The mobile camera UI (Phase 2).
- The web filter UI (Phase 3) — endpoint exists in 1.7, but the
  consumer UI doesn't.
- Reviews + suggestions UX (Phase 4).
