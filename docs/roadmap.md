# Roadmap

The phase plan. Each phase ends with a real demo. The autonomous
delivery loop reads the **Next up** queue below to pick its next PR;
each entry links to a `docs/plans/phase-N.md` subplan with the gory
details.

## Next up

The loop takes these in order, top-down. `[BLOCKED]` prefix means
"skip; needs a human to clear." See `docs/delivery-playbook.md` for
the merge / review / status rules.

**Phase 3** ⭐ Dietary filter UI. Subplan: `docs/plans/phase-3.md`.

1. **Phase 3.2 — Mobile profile onboarding (6 taps)** (`docs/plans/phase-3.md#32`) — this PR
2. **Phase 3.3 — Mobile filtered restaurant page** (`docs/plans/phase-3.md#33`)
3. **Phase 3.4 — Transparency layer + one-tap override** (`docs/plans/phase-3.md#34`)
4. **Phase 3.5 — Strict-mode toggle** (`docs/plans/phase-3.md#35`)
5. **Phase 3.6 — Web filtered restaurant page** (`docs/plans/phase-3.md#36`)
6. **Phase 3.7 — `applyProfile` in filter-engine** (`docs/plans/phase-3.md#37`)
7. **Phase 3.8 — Web profile onboarding** (`docs/plans/phase-3.md#38`)
8. **Phase 3.9 — Shareable filter URLs** (`docs/plans/phase-3.md#39`)

### Done

- ✅ subtask: master CI green (#112)
- ✅ Phase 1.1 — Devise JWT signup/login/logout/refresh (#124)
- ✅ Phase 1.2 — OmniAuth Apple + Google (#128)
- ✅ chore: default all PRs to auto-merge (#129)
- ✅ Phase 1.3 — `GET/PATCH /api/v1/profile` (#130)
- ✅ Phase 1.4 — full ingredient port: 1,096 ingredients (#131)
- ✅ Phase 1.5 — Avo admin at `/admin` (#132)
- ✅ Phase 1.6 — OpenAPI codegen for `packages/api-types` (#133)
- ✅ Phase 1.7 — Restaurant + Item read endpoints with filter (#134)
- ✅ Phase 2.1 — AnthropicClient service (#136)
- ✅ Phase 2.2 — IngestionRun + IngestionItem state machine (#137)
- ✅ Phase 2.3 — ExtractMenuJob + ActiveStorage wiring (#138)
- ✅ Phase 2.4 — ResolveIngredients + ResolveTags jobs (#139)
- ✅ Phase 2.5 — admin verify UI + 80%-accepted publish (#140)
- ✅ Phase 2.6 — mobile camera + ingestion runs API (#141)
- ✅ Phase 2.7 — mobile swipe-verify UI + ingestion item PATCH (#142)
- ✅ Phase 2.8 — web URL/PDF entrypoint (#143)
- ✅ Phase 2.9 — cost + latency dashboard at /admin/dashboard (#144)
- ✅ Phase 3 — subplan committed (#145)
- ✅ Phase 3.1 — production-ready dietary profile seeds (#146)

After Phase 3 ships, the loop will draft `docs/plans/phase-4.md` (reviews + accounts) the same way.

## Phase 0 — Foundation ✅

- [x] Archive 2020 codebase to `_legacy/`
- [x] pnpm + Turborepo monorepo
- [x] Rails 8 API skeleton (config, schema, models, seeds)
- [x] Next.js 15 web skeleton
- [x] Expo mobile skeleton
- [x] Shared TS packages: api-types, filter-engine (with tests),
      ui-tokens, eslint-config
- [x] CI workflow committed (failing on master — see Next-up #1)
- [x] ADR 0001 capturing every stack pick
- [x] Delivery playbook + status log + phase subplans

**Demo:** all three apps say "hello" against the same Rails API. Held
back by the master-CI subtask.

## Phase 1 — Schema + auth + admin ✅

Subplan: `docs/plans/phase-1.md`. All 7 tasks merged (#124, #128,
#130, #131, #132, #133, #134) plus the auto-merge policy chore (#129).

**Demo (achieved 2026-04-29):** admin can create a restaurant + 10-item
menu in `/admin` (Phase 1.5); web and mobile call
`GET /api/v1/restaurants/:id/items?profile=…` (Phase 1.7) and items
either show or carry a transparent reason for being hidden.

## Phase 2 — AI ingestion MVP ✅

Subplan: `docs/plans/phase-2.md`. All 9 tasks merged
(#136, #137, #138, #139, #140, #141, #142, #143, #144).

**Demo (achieved 2026-04-30):** end-to-end ingestion pipeline shipped
— web URL/PDF entrypoint OR mobile multi-page camera capture →
ExtractMenuJob (vision) → ResolveIngredients/ResolveTags jobs →
IngestionItems staged → admin verify (Avo) or mobile swipe-verify
→ 80%-accepted threshold flips run + restaurant to :published.
Cost + latency dashboard at `/admin/dashboard` tracks the $0.25/
50-item-menu target.

**Remaining gap:** Phase 2.3 + 2.4 ship with mocked-AnthropicClient
specs. The cassette stubs need a human with `ANTHROPIC_API_KEY` to
record real interactions before "live demo-ready" is true.

**Demo (original target text):** photograph a real Durango menu in person; 60 seconds later
the items appear staged; 5 minutes of swiping promotes them to live.

## Phase 3 — Dietary filter (weeks 7–9)

Subplan: `docs/plans/phase-3.md` (drafted at end of Phase 2).

- Profile onboarding (6 taps to working filter)
- Curated dietary-profile presets fully wired
- Filtered restaurant page (mobile + web) — `applyProfile` from
  filter-engine
- Transparency layer: every hidden item shows reason
- One-tap override per item ("show anyway")
- Strict-mode toggle (hides anything not `confidence: confirmed`)
- Shareable filter URLs (encode profile in a token)

**Demo:** open the app, pick "Celiac + tree-nut allergy", scan a real
menu, see only the dishes that pass. Hidden items each say *why*.

## Phase 4 — Reviews + accounts (weeks 10–11)

Subplan: `docs/plans/phase-4.md`.

- Per-item reviews (1–5 + text + photo)
- Review moderation queue
- User profile pages
- "My filtered menus" history
- Restaurant claim flow (domain-email verification)
- Suggestion queue UX for community edits

**Demo:** a logged-in user reviews a dish from a restaurant they
filtered to; an owner claims that restaurant.

## Phase 5 — Launch (week 12)

Subplan: `docs/plans/phase-5.md`.

- Seed 30 Durango restaurants via the ingestion pipeline
- App Store + Play Store submission
- SEO landing pages: `/durango/gluten-free`, `/durango/vegan`, etc.
- PostHog funnels: app_open → profile_set → menu_filtered →
  restaurant_tap
- Public launch posts + outreach to Durango press

**Demo:** real users on a Friday night using it to pick where to eat.

## Discovered (loop-added followups)

The loop appends here when work surfaces a new task that doesn't
belong in the current phase. Humans triage these into the appropriate
phase or "Next up" queue.

(empty)

## What we are explicitly NOT doing in v1

- 14-tier user levels / gamification
- Restaurant-deal coupons
- Reservations / delivery integrations
- Social feed
- A separate native iOS / native Android codebase
