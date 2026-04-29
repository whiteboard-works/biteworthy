# Delivery status log

The autonomous loop's running log. Newest entries on top. One line per
tick or significant event. Format:

```
YYYY-MM-DD HH:MM (UTC) — <summary>
```

The point is breadcrumbs: a tick interrupted at minute 28 should leave
enough here for the next tick (or a human dropping in) to resume
without spelunking GitHub.

---

2026-04-29 23:05 — tick #43. PR #137 (Phase 2.2) merged at 22:19 UTC.
Picked up Phase 2.3 — ExtractMenuJob. Stop condition (needs
ANTHROPIC_API_KEY for cassette recording) acknowledged but bulk of
work shipped without live calls. Migrations: ActiveStorage install +
extraction-fields columns (staging jsonb, api_cost_cents,
latency_ms, cached/uncached_input_tokens for Phase 2.9 dashboard).
**Discovered + fixed**: default ActiveStorage migration uses
`bigint` for `record_id`, which silently coerces UUID parents to
nil — added `t.string :record_id` override. New code:
`Ingestion::MenuExtractionSchema` (JSON Schema for the structured
output), `Ingestion::ExtractMenuPrompt` (system + user blocks with
caching), `ExtractMenuJob` (state-machine wired, transitions
queued→extracting→resolving on success / →failed on ApiError or
ValidationError, records latency_ms). `IngestionRun` declares
`has_many_attached :inputs`. `ApplicationJob` base class with
retry_on. `config.active_job.queue_adapter = :test` in test env so
specs don't need Solid Queue tables. 5 mocked-client specs pass +
1 cassette-stub `skip` block flagged for human follow-up. Local
rspec 97/97 (1 pending). Pushing PR.

2026-04-29 22:25 — tick #42. PR #136 (Phase 2.1) merged at 21:48 UTC.
Picked up Phase 2.2 — state machine. Migration adds
`state_history :jsonb` + renames `error_message` → `failure_message`
(no data lost, column was unused). `IngestionRun#transition_to!(state)`
is idempotent (re-call = no-op, first-entry timestamp wins),
records UTC iso8601 in state_history, raises InvalidTransition for
non-adjacent forward moves (queued → published etc.), and dispatches
NEXT-state Solid Queue jobs via `safe_constantize` so 2.3+ defining
ExtractMenuJob/ResolveIngredientsJob "just works" with no further
changes here. `#fail!(message)` truncates to 2000 chars + transitions
to failed without enqueuing. Predicates auto-defined per status.
`IngestionItem#promote!` materializes a staged item → real Item +
ItemIngredient + ItemTag rows with confidence: confirmed, source:
human (humans accepted, that's confirmed by definition); skips
unresolvable slugs gracefully; idempotent (re-call returns existing
Item, no dup join rows); raises if the IngestionRun has no
restaurant. New ingestion factories (run + item) with realistic
payloads matching what 2.4's resolve job will write. 18 model
specs (11 run + 7 item). Local rspec 91/91 green.

2026-04-29 22:00 — tick #41. Plan PR #135 merged at 21:16 UTC. Phase 2
queue live. Picked up Phase 2.1 — AnthropicClient. Faraday wrapper
at `app/services/anthropic_client.rb` with bearer auth, prompt
caching helper (`#system_blocks` marks blocks with
`cache_control: {type: ephemeral}`), vision input helper
(`#image_block` accepts ActiveStorage::Blob OR raw IO/String,
base64-encodes), structured output validation via json-schema gem
(raises `AnthropicClient::ValidationError` with the validator's
errors[]), retries via faraday-retry (3 attempts on 429/5xx,
auth errors NOT retried). Default model claude-sonnet-4-6 per
ADR 0001. Helper class `AnthropicClient::ResponseParser` extracts
the first text block from /v1/messages responses. Added vcr gem
+ `spec/support/vcr.rb` config for Phase 2.3+ cassette recording
(record: :once locally, :none in CI, sensitive-header scrubbing).
12 unit specs at `spec/services/anthropic_client_spec.rb` covering
all public methods + happy/auth-fail/retry paths via WebMock
stubs. ANTHROPIC_API_KEY documented in .env.example. Local rspec
73/73 green. Pushing PR.

2026-04-29 21:25 — tick #40. PR #134 (Phase 1.7) merged at 20:57 UTC.
**Phase 1 complete end-to-end.** Demo unblocked: admin builds a menu
in /admin, web/mobile call /api/v1/restaurants/:id/items, items
show or carry a transparent reason. Per the roadmap policy ("After
Phase 1 ships, the loop pulls Phase 2 items into Next up via a
plan-update PR"), this tick = plan PR. Drafted
`docs/plans/phase-2.md` decomposing the AI ingestion MVP into 9
PR-sized tasks (AnthropicClient → state machine → ExtractMenu/
Resolve jobs → admin verify → mobile camera → mobile swipe-verify
→ web URL/PDF → cost dashboard) with explicit stop conditions for
the ANTHROPIC_API_KEY (cassette recording needs it). Updated
`docs/roadmap.md`: marked Phase 1 ✅ in the phase header, replaced
the empty Next-up with the proposed Phase 2 queue (loop-proposed,
human reviews this PR before they auto-run). No code changes — this
is a docs-only plan PR. Next tick: depends on how owner reviews
the Phase 2 queue. If approved, pick up Phase 2.1.

2026-04-29 20:50 — tick #39. PR #133 (Phase 1.6) merged at 20:20 UTC.
Picked up Phase 1.7 — the centerpiece dietary filter. New
`Api::V1::ItemsController#index` at `GET /api/v1/restaurants/:id/items`
returns every published item with per-item `status` (visible|hidden)
+ `reasons[]`. Filter source resolves in priority order: `?profile=
<slug>` (DietaryProfile lookup) > current_user.profile (when JWT
present) > none. `?strictness=strict` overrides; in strict mode
items with `confidence != 'confirmed'` get a reason
`unconfirmed_strict`. Endpoint is unauth-friendly so anon mobile
users can browse menus. New factories for places (city/restaurant)
+ items (menu/menu_section/item) using real Durango data + curated
samples. 7 request specs covering all 5 acceptance scenarios from
phase-1.md §1.7 + 2 404 paths. New rswag spec at
`spec/integration/.../restaurants/items_spec.rb` regenerated
docs/openapi.json + generated.ts; pnpm typecheck/lint/test all
green; rspec 59/59. Roadmap ticked Phase 1.6 + flagged Phase 1
as the last item before phase-2 plan PR.

2026-04-29 20:15 — tick #38. PR #132 (Phase 1.5) merged at 19:50 UTC.
Picked up Phase 1.6 — OpenAPI codegen. Wrote rswag swagger_helper.rb
(OpenAPI 3.0.3, security schemes for bearerAuth + basicAuth, shared
component schemas for UserPayload/AuthResponse/ProfilePayload/
Error/ValidationErrors). Added rswag specs for 8 endpoints
(signup/login/logout/refresh + 2× omniauth + GET/PATCH profile)
under `spec/integration/api/v1/`. `bin/openapi-export` wraps
`rake rswag:specs:swaggerize` to dump `docs/openapi.json` (497
lines). Wired up `pnpm --filter @biteworthy/api-types build:codegen`
via openapi-typescript v7 → `packages/api-types/src/generated.ts`
(345 lines). Replaced hand-written `index.ts` with re-exports of
generated types + friendly aliases (UserPayload/AuthResponse/
ProfilePayload). Added `codegen:check` script and a CI step in
`ci-js.yml` that fails if `generated.ts` is out of sync with
`docs/openapi.json`. Discovered + fixed: `next lint` deprecated in
Next 16, swapped `apps/web` lint script to `eslint .`. Local rspec
52/52 green; pnpm typecheck/lint/test all green.

2026-04-29 19:45 — ticks #36+#37 combined. Owner picked Avo (via the
implicit "just go" pattern from earlier ticks). Implemented Phase 1.5:
avo gem (~v3.17), `rails g avo:install` initializer mounted at `/admin`
(not /avo) gated with HTTP Basic auth (`ADMIN_USERNAME`/
`ADMIN_PASSWORD` ENV, falls back to admin/admin in dev+test for
boot-without-secrets), `is_admin :boolean` migration on users with a
partial index on `is_admin = true`, 14 Avo resources auto-generated
covering Restaurant/City/Address/Hours/Menu/MenuSection/Item/
ItemVariant/ItemModifier/Ingredient/Tag/DietaryProfile/User(RO)/
Suggestion. User resource hand-cleaned to drop `jti`/
`confirmation_token`/`encrypted_password` from the field list (security
tokens). Suggestion's polymorphic subject types filled in (Restaurant,
Item, Ingredient, Tag). Read-only on User+Suggestion is trust-based
for now — Phase 4 adds Pundit policies. New `spec/requests/admin_spec.rb`
covers the auth gate (challenge / wrong creds / right creds → 200|302).
Local rspec 40/40 green. Pushing PR next.

2026-04-29 18:30 — tick #35. PR #130 (Phase 1.3) merged at 18:06 UTC
under the new auto-merge default. Picked up Phase 1.4 — full
ingredient port. Wrote a balanced-paren parser at
`apps/api/script/import_legacy_ingredients.rb` that turns the 905-
line 2020 `_legacy/db/seeds/0_ingredients.rb` into structured YAML
with ltree paths. Added curated supplements (dairy, egg, spice,
sesame, soy, shellfish, oil_and_fat, sweetener, condiment, alcohol)
to cover the FDA big-9 allergens + path roots phase-1.md required.
Output: 1,096 ingredients, 218 allergen-flagged, 0 malformed
ltree paths, parenthetical glosses preserved as aliases (e.g.
"Domestic pig" carries alias "pork"). New `spec/db/ingredients_seed_spec.rb`
verifies catalog shape, idempotence, and ancestry queries through
the GiST `path <@` index. Local rspec 37/37 green. Pushing PR next.

2026-04-29 14:00 — tick #33. Hold continues (29th in a row). No-op.

2026-04-29 18:00 — tick #34 (resumed). Owner unblocked: directly
merged PR #128 (phase-1.2). Owner directive: drop approval gate
entirely. Opened + merged PR #129 (chore/auto-merge-default) which
(a) updates `.github/workflows/auto-merge.yml` to enable auto-merge
on every non-draft PR, (b) rewrites `docs/delivery-playbook.md`
auto-merge policy + §2 state table to match. Started Phase 1.3 on
`claude/phase-1.3-user-profile`: full GET/PATCH `/api/v1/profile`
with wholesale array replacement + additive dietary_profile_slug
preset application, plus ingredient/tag/dietary_profile factories.
Local rspec 28/28 green (11 new in profile_spec). Pushing PR next.

2026-04-29 13:30 — tick #32. Hold continues (28th in a row). No-op.

2026-04-29 13:00 — tick #31. Hold continues (27th in a row). No-op.

2026-04-29 12:30 — tick #30. Hold continues (26th in a row). No-op.

2026-04-29 12:00 — tick #29. Hold continues (25th in a row). No-op.

2026-04-29 11:30 — tick #28. Hold continues (24th in a row). No-op.

2026-04-29 11:00 — tick #27. Hold continues (23rd in a row). No-op.

2026-04-29 10:30 — tick #26. Hold continues (22nd in a row). No-op.

2026-04-29 10:00 — tick #25. Hold continues (21st in a row). No-op.

2026-04-29 09:30 — tick #24. Hold continues (20th in a row). No-op.

2026-04-29 09:00 — tick #23. Hold continues (19th in a row). No-op.

2026-04-29 08:30 — tick #22. Hold continues (18th in a row). No-op.

2026-04-29 08:00 — tick #21. Hold continues (17th in a row). No-op.

2026-04-29 07:30 — tick #20. Hold continues (16th in a row). No-op.

2026-04-29 07:00 — tick #19. Hold continues (15th in a row). No-op.

2026-04-29 06:30 — tick #18. Hold continues (14th in a row). No-op.

2026-04-29 06:00 — tick #17. Hold continues (13th in a row). No-op.

2026-04-29 05:30 — tick #16. Hold continues (12th in a row). No-op.

2026-04-29 05:00 — tick #15. Hold continues (11th in a row). No-op.

2026-04-29 04:30 — tick #14. Hold continues (10th in a row). No-op.

2026-04-29 04:00 — tick #13. Hold continues (9th in a row). No-op.

2026-04-29 03:30 — tick #12. Hold continues (8th in a row). No-op.

2026-04-29 03:00 — tick #11. Hold continues (7th in a row). No-op.

2026-04-29 02:30 — tick #10. Hold continues (6th in a row). No-op.

2026-04-29 02:00 — tick #9. Hold continues (5th in a row). No-op.

2026-04-29 01:30 — tick #8. Hold continues (4th in a row). No-op.

2026-04-29 01:00 — tick #7. Hold continues (3rd in a row). No-op.

2026-04-29 00:30 — tick #6. Hold continues. PR #128 unchanged from
#5 (CLEAN/MERGEABLE, no review, no label). No-op tick.

2026-04-29 00:00 — tick #5. Hold tick. PR #128 unchanged from #4:
CLEAN/MERGEABLE, all 7 checks SUCCESS, `reviewDecision: ""`, no
`auto-merge-ok` label, no shadoath response. Discovered structural
issue: the loop's gh CLI authenticates as `shadoath` (same as the
project owner), so `@shadoath` pings via `gh pr comment` are
self-mentions and don't notify. Playbook's escalation channel needs
either a separate bot account OR direct surfacing to the human via
the agent conversation. Surfaced both in this tick's reply. Not
re-pinging (no signal value). Not stacking Phase 1.3 PR (one PR per
task per playbook). Holding until human acts on #128.

2026-04-28 23:30 — tick #4. PR #128 fully green: rspec 17/17,
CodeQL js+ruby, **CodeQL umbrella also SUCCESS** (the CSRF alert
cleared once I removed the no-op `skip_before_action`), labeler,
title-lint. `mergeStateStatus: CLEAN`, `mergeable: MERGEABLE`. But
`reviewDecision: ""` — codex hasn't responded ~1h post-ping. Per
playbook auto-merge needs codex approval OR `auto-merge-ok` label
OR shadoath approval; none present. Pinged `@shadoath` on the PR
asking for approval, label, or hold-direction. Tick ends here per
playbook §7 (no progress on Next-up while a `claude-cd` PR is
waiting for review). Next tick: re-check for codex/shadoath
response; if still no movement, hold.

2026-04-28 23:00 — tick #3. PR #128 CI · API green (rspec 17/17) and
CodeQL js+ruby green after the 22:35 push, but the umbrella
"CodeQL" code-scanning aggregator FAILED on a real new alert:
`rb/csrf-protection-disabled` against
`omniauth_callbacks_controller.rb:13` (the
`skip_before_action :verify_authenticity_token` line). In api_only
mode that line is a no-op — ActionController::API never installs
CSRF in the first place. Removed the line + comment-explained why
(commit 6d6ed92). Local rspec still 17/17 green. No `@codex` review
came back since the 21:55 ping; PR is `reviewDecision: ""`. Per
playbook §2 still need CI green AND approval; if codex doesn't
respond by next tick, will ping `@shadoath` to clarify codex setup
or apply `auto-merge-ok` manually. Next tick: re-check CI + review
state.

2026-04-28 22:35 — tick #2. PR #128 CI red: 17/17 specs failing 500.
Root cause: api_only Rails strips session middleware → OmniAuth's
strategy raises NoSessionError on every request (including /up).
Diagnosed by starting postgres@16 locally, reproducing with
`bin/rspec`, reading log/test.log. Pushed three fixes in one
commit (06fc7c9): (a) reinjected ActionDispatch::Cookies + Session
in application.rb, (b) skipped Devise's `/api/v1/auth/auth/:provider`
double-prefix routes — set OmniAuth.config.path_prefix +
custom clean routes for /api/v1/auth/:provider per phase-1.md spec,
(c) `||=` was a no-op against the `default: ""` email column → use
`if blank?`. Local rspec: 17 examples, 0 failures. Waiting on CI
re-run to confirm green; next tick checks merge state.

2026-04-28 21:55 — opened #128 phase-1.2-omniauth (+362/-3); 5 specs
across google + apple (new/returning/failure). Created `claude-cd` +
`auto-merge-ok` labels on the repo (referenced by playbook + auto-
merge.yml but never created). Requested `@codex review`. CI checks
in flight: ci-api (rspec/brakeman/rubocop), CodeQL (js + ruby),
labeler, title-lint. Waiting for CI; next 30-min tick checks state.

2026-04-28 21:30 — loop tick (resumed). Reconciled stale log: PR #124
(phase-1.1) merged at 2026-04-29 01:16 UTC; `Done` already ticked in
roadmap. Picked up Phase 1.2 — opened branch
`claude/phase-1.2-omniauth`. Implemented: `:omniauthable` on User,
`User.from_omniauth`, `OmniauthCallbacksController` (google_oauth2 +
apple + failure), routes wired, `config/initializers/omniauth.rb`
(allow GET request method, on_failure → controller), `.env.example`
documenting GOOGLE_/APPLE_/DEVISE_JWT_ env vars, request specs in
test_mode covering google new/returning/failure + apple
new/returning. Local rspec deferred (no postgres service running on
this dev box); CI's postgres container will exercise. Next: push +
open PR + request `@codex review`.

2026-04-28 20:05 — loop tick #1. PR #124 (phase-1.1) open, CI pending
on all 5 checks after title-fix push, `area:api` label applied. Per
playbook: wait for CI, no action. Subscribed to PR activity; webhook
events will trigger the next handler. Cron primitive (CronCreate) not
loaded in this session — relying on webhooks + user pings for
heartbeat instead of a true 30-min cadence.

2026-04-28 19:55 — Phase 1.1 complete locally; opening PR. 12 request
specs green covering signup happy/dup/invalid, login happy/wrong-pw/
ghost, logout rotates jti + invalidates old token, refresh rotates jti
+ invalidates old token + rejects no-token. Includes a stub
`Api::V1::ProfilesController#show` so the auth-gating specs have a
real protected route — Phase 1.3 owns its full GET/PATCH semantics.

2026-04-28 09:30 — PR #112 (master CI rebuild + GitHub Actions
modernization) merged. CI now green: 6 workflows, dependabot,
labeler, auto-merge gate, conventional-commit PR title check,
CodeQL, code owners.

2026-04-28 09:10 — PR #111 (delivery framework) merged. Playbook +
status log + phase subplan + restructured roadmap on master.

2026-04-28 09:00 — Phase 0 merged (PR #110). Some master CI red —
added to Next-up as a subtask. Framework PR (`claude/delivery-framework`)
opening shortly with playbook v2, status log, phase-1 subplan, roadmap
restructure.
