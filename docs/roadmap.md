# Roadmap

The phase plan. Each phase ends with a real demo. The autonomous
delivery loop reads the **Next up** queue below to pick its next PR;
each entry links to a `docs/plans/phase-N.md` subplan with the gory
details.

## Next up

The loop takes these in order, top-down. `[BLOCKED]` prefix means
"skip; needs a human to clear." See `docs/delivery-playbook.md` for
the merge / review / status rules.

**Phase 2** ⭐ AI ingestion MVP. Subplan: `docs/plans/phase-2.md`. This batch is **proposed by the loop** (this PR is the plan-update PR); humans review it before the items auto-run.

1. **Phase 2.1 — AnthropicClient service** (`docs/plans/phase-2.md#21`) — this PR
2. **Phase 2.2 — IngestionRun + IngestionItem state machine** (`docs/plans/phase-2.md#22`)
3. **Phase 2.3 — ExtractMenuJob** (`docs/plans/phase-2.md#23`) — depends on 2.1, 2.2; needs `ANTHROPIC_API_KEY` for VCR cassette recording
4. **Phase 2.4 — ResolveIngredients + ResolveTags jobs** (`docs/plans/phase-2.md#24`) — depends on 2.3; needs `ANTHROPIC_API_KEY`
5. **Phase 2.5 — Item promotion + admin verify UI** (`docs/plans/phase-2.md#25`)
6. **Phase 2.6 — Mobile multi-page camera capture + upload** (`docs/plans/phase-2.md#26`)
7. **Phase 2.7 — Mobile swipe-verify UI** (`docs/plans/phase-2.md#27`)
8. **Phase 2.8 — Web: paste-URL / upload-PDF entrypoint** (`docs/plans/phase-2.md#28`)
9. **Phase 2.9 — Cost + latency dashboard in admin** (`docs/plans/phase-2.md#29`)

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

After Phase 2 ships, the loop will draft `docs/plans/phase-3.md` (dietary filter UI) the same way.

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

## Phase 2 — AI ingestion MVP (weeks 4–6) ⭐

Subplan: `docs/plans/phase-2.md` (drafted at end of Phase 1).

- AnthropicClient service (Faraday + Bearer + prompt caching)
- IngestionRun + IngestionItem state machine
- Solid Queue jobs: ExtractMenu, ResolveIngredients, ResolveTags
- Mobile: multi-page camera capture → upload → wait → swipe-verify UI
- Web: paste URL or upload PDF → verify
- Cost + latency dashboard in admin

**Demo:** photograph a real Durango menu in person; 60 seconds later
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
