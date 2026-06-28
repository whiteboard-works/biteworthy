# AGENTS.md — apps/api (Rails)

<!-- BEGIN codex-review-guidelines (managed by AGENTS-REVIEW-ROLLOUT.md) -->
## Review guidelines

**Context:** The Rails API behind BiteWorthy's dietary filter. Allergen safety and the E1–E13 legal columns are the stakes: a wrong join-row confidence or a dropped safety/consent column can show an unsafe item to an allergic user or break a legal guarantee. (See the repo-root `AGENTS.md` for the cross-package filter-parity and analytics contracts.)

GitHub surfaces only P0/P1 findings, so phrase issues as block-worthy. CI runs RSpec + Brakeman (blocking) here; **RuboCop runs with `continue-on-error` (informational) — do not block on RuboCop/style.** Don't restate those gates.

Block a PR (P0/P1) when it:

- **Weakens an allergen-safety or legal-consent column.** On `user_profiles`: `avoid_ingredient_ids` / `avoid_tag_ids`, `strictness`, and `disclaimer_acknowledged_at`. On `users`: `age_confirmed_at` and `terms_accepted_at`. These columns exist for E1–E13 remediation — removing, nulling, or bypassing them (in a migration or a controller before-filter) is a P0 regression.
- **Sets the `confidence` on an `ItemIngredient` / `ItemTag` join row wrong.** `confidence` controls whether strict/allergy users see an item (they see only `confirmed`); a join row created or promoted with the wrong confidence silently surfaces an unconfirmed item as safe. (`confidence` and `source` are validated against `CONFIDENCE` / `SOURCES` — keep promotions consistent with the existing `IngestionItem#promote!` / `SuggestionResolver#apply!` paths.)
- **Adds or changes an endpoint without an rswag spec + regen.** A new/changed endpoint needs an rswag spec plus `bin/openapi-export` and `@biteworthy/api-types` `build:codegen` in the same PR. Many endpoints still lack rswag specs, and `codegen:check` only catches drift for endpoints that *have* one — so any spec-less endpoint's hand-written types are an unguarded drift surface. Don't add new spec-less endpoints.
- **Adds/changes an Anthropic call without a VCR cassette.** Ingestion jobs use `AnthropicClient`; CI runs with `record: :none`, so a new/changed AI call without a committed cassette in `spec/cassettes/` makes a live HTTP request that fails and surfaces key-not-set errors.
- **Writes `items.ingredient_ids` / `items.tag_ids` directly** instead of through the `ItemIngredient`/`ItemTag` join rows (their `sync_*` callbacks maintain the arrays).
- **Modifies an already-shipped migration** (the migration guard blocks it) — add a new migration instead.

Also treat these normally-lower-severity issues as P1 so they surface:

- A new request path (controller action) that does an `items` query without `includes`/limit (N+1 or unbounded) on the menu/filter hot path.

For architecture and conventions, also follow CLAUDE.md and the repo-root `AGENTS.md`.
<!-- END codex-review-guidelines -->
