# Roadmap

The phase plan. Each phase ends with a real demo. The autonomous
delivery loop reads the **Next up** queue below to pick its next PR;
each entry links to a `docs/plans/phase-N.md` subplan with the gory
details.

## Next up

The loop takes these in order, top-down. `[BLOCKED]` prefix means
"skip; needs a human to clear." See `docs/delivery-playbook.md` for
the merge / review / status rules.

**Phase 5** ⭐ Launch (Durango). Subplan: `docs/plans/phase-5.md`.

1. **Phase 5.1.1 — migrate API hosting from Fly.io to Kamal + Hetzner CX22 + Neon Postgres** (`docs/plans/phase-5.md#511--migrate-api-hosting-to-kamal--hetzner-cx22--neon-postgres`) — this PR (the next loop tick picks it up). Reverses the original 5.1 Fly.io pick at human request. Ships the deploy.yml + ADR 0007 + README rewrite + secrets template; the Hetzner box, Neon project, GHCR token, and DNS A-record are the human bootstrap. Reuses unchanged: Dockerfile, docker-entrypoint, smoke task, and every Phase 5.2+ wiring.
2. **[BLOCKED] Phase 4.11.0 / 4.11.2-cassette — Record the live AnthropicClient cassette** (combined: VCR's body matching means the 4.11.2 prompt change auto-supersedes the older cassette; one recording covers both). **Blocked on Anthropic daily-cap reset at 2026-05-01 00:00 UTC** — retry after that. Holdover from Phase 4.11; not a launch blocker (the structural code is on master) but should land before Phase 5.7's seed task mass-ingests real Durango menus.
3. **Phase 5.10 — press kit + Durango outreach** (`docs/plans/phase-5.md#510--press-kit--outreach-durango-launch`).
4. **Phase 5.8-wiring — instrument 9 funnel events end-to-end** (followup to #179; needs `posthog-js` + `posthog-react-native` installed and the call-site instrumentation.) Decoupled because each surface PR is small + reviewable on its own.
5. **Phase 5.9-wiring — generate binary assets + screenshot routes + EAS submit** (followup to #180; needs Apple/Google dev accounts + lawyer signoff on /privacy + /terms).

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
- ✅ Phase 3.2 — mobile profile onboarding (6 taps) (#147)
- ✅ Phase 3.3 — mobile filtered restaurant page (#148)
- ✅ Phase 3.4 — transparency chips + show-anyway override (#149)
- ✅ Phase 3.5 — strict-mode toggle (#150)
- ✅ Phase 3.6 — web filtered restaurant page (#151)
- ✅ Phase 3.7 — applyProfile + display helpers consolidated in filter-engine (#152)
- ✅ Phase 3.8 — web profile onboarding (#153)
- ✅ Phase 3.9 — shareable filter URLs (#154) — **Phase 3 feature-complete**
- ✅ Phase 4 — subplan committed (#155)
- ✅ Phase 4.1 — real session cookies + login/signup (#156)
- ✅ Phase 4.2 — persistent "never hide this dish" override (#157)
- ✅ Phase 4.3 — review API + photo attachment (#158)
- ✅ Phase 4.4 — mobile review UX (#159)
- ✅ Phase 4.5 — web review UX (#160)
- ✅ Phase 4.6 — review moderation queue (#161)
- ✅ Phase 4.7 — public user profile pages (#162)
- ✅ Phase 4.8 — "My filtered menus" history (#163)
- ✅ Phase 4.9 — restaurant claim flow with domain-email verification (#164)
- ✅ Phase 4.10 — suggestion queue UX for community edits (#165) — **Phase 4 feature-complete**
- ✅ Phase 4.11 — subplan committed (#166)
- ✅ Phase 4.11.1 — image_bbox column + DishPhotoCropper service (#167)
- ✅ Phase 4.11.3 — IngestionItem promote attaches cropped dish photo (#168)
- ✅ Phase 4.11.4 — render cropped dish photos on restaurant pages (#169)
- ✅ Phase 4.11.2 — extend menu-extraction schema + prompt with image bboxes (#170) — **Phase 4.11 structurally complete; live cassette recording is the only remaining task**
- ✅ Phase 5 — subplan committed (#171)
- ✅ Phase 5.1 — production API deploy wiring: Fly.io + Dockerfile + smoke task (#172)
- ✅ Phase 5.2 — production SMTP + email smoke task (#173)
- ✅ Phase 5.3 — production blob storage on Cloudflare R2 + backfill task (#174)
- ✅ Phase 5.4 — production web deploy wiring: vercel.json + sitemap + cookie domain (#175) — **Phase 5 production infrastructure structurally complete (5.1 API + 5.2 SMTP + 5.3 R2 + 5.4 web)**
- ✅ Phase 5.5 — marketing landing page at / (#176)
- ✅ Phase 5.6 — SEO city/diet pages at /durango/[diet] (#177)
- ✅ Phase 5.7 — durango batch ingest task + csv template (#178)
- ✅ Phase 5.8 — analytics abstraction + event taxonomy (#179) — **structural; wiring follow-up queued at Next-up #4**
- ✅ Phase 5.9 — privacy + terms + app store listing templates (#180) — **structural; wiring follow-up queued at Next-up #5**

After Phase 4 ships, the loop will draft `docs/plans/phase-5.md` (Durango launch) the same way.

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

## Phase 3 — Dietary filter (weeks 7–9) ✅

Subplan: `docs/plans/phase-3.md` (drafted at end of Phase 2).

- Profile onboarding (6 taps to working filter)
- Curated dietary-profile presets fully wired
- Filtered restaurant page (mobile + web) — `applyProfile` from
  filter-engine
- Transparency layer: every hidden item shows reason
- One-tap override per item ("show anyway")
- Strict-mode toggle (hides anything not `confidence: confirmed`)
- Shareable filter URLs (encode profile in a token)

**Demo (achieved 2026-04-30):** open the app, pick "Celiac + tree-nut
allergy", scan a real menu, see only the dishes that pass. Hidden
items each say *why*. Tap "show anyway" on one and it re-appears
client-side. Share a filtered link via `/r/<slug>?p=<token>` and the
recipient sees the same view without signing in.

## Phase 4 — Reviews + accounts (weeks 10–11) ✅

Subplan: `docs/plans/phase-4.md`.

- Per-item reviews (1–5 + text + photo)
- Review moderation queue
- User profile pages
- "My filtered menus" history
- Restaurant claim flow (domain-email verification)
- Suggestion queue UX for community edits

**Demo (achieved 2026-04-30):** a logged-in user reviews a dish
from a restaurant they filtered to; an owner claims that
restaurant via domain-email verification; a contributor suggests
a missing-ingredient fix and the owner accepts it from the queue.

## Phase 4.11 — Per-dish photo extraction (interstitial)

Subplan: `docs/plans/phase-4.11-dish-photos.md`. User-requested
followup. Pulls each dish photo out of the source menu page and
attaches it to the resulting Item, so the restaurant page can
render the menu with real food photos. Includes the long-deferred
Phase 2.3 cassette PR as the prerequisite (4.11.0).

**Demo:** open a restaurant page; items that had a photo on the
source menu page render with the cropped photo alongside the
name + description.

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

- **Wire `jest-expo` preset + `@testing-library/react-native` for the
  mobile app, AND wire `@testing-library/react` + jsdom for the web
  app** — surfaced during Phase 3.5; reinforced by Phase 4.11.4's
  inability to ship a JSX render snapshot for the new dish-photo
  `<Image>` / `<img>` on either side. Mobile tests currently run
  pure-TS only; importing any screen module (which transitively
  imports react-native ESM) fails Jest's default transformer. Web
  tests are also pure-TS — there's no `@testing-library/react` dep
  and no `vitest.config.ts`, so a `.tsx` test would set new precedent.
  Setup change in its own PR (one for each app); once landed,
  retroactively add the deferred snapshots from 3.2 / 3.3 / 3.4 /
  3.5 / 4.11.4 (web RestaurantClient ItemRow + mobile [id].tsx
  ItemRow asserting `photo_url` renders into an `<img>` / `<Image>`
  when set, doesn't render when null).
- **Auto-merge race lost a follow-on commit on PR #150**. After the
  initial push, a second commit (the prior version of this Discovered
  note) was added before CI finished — auto-merge had already enabled
  on the first sha and squashed without the second commit's diff.
  Either tighten the loop's flow (push everything in one go) or
  consider gating auto-merge on a manual "ready" label after final
  push.
- ~~Consolidate web + mobile pure helpers~~ — done in Phase 3.7 (#152).
  All display helpers (`hiddenReasonLabel`, `groupItemsBySection`,
  `applyOverrides`) now live in `@biteworthy/filter-engine` and are
  the single source of truth.

## What we are explicitly NOT doing in v1

- 14-tier user levels / gamification
- Restaurant-deal coupons
- Reservations / delivery integrations
- Social feed
- A separate native iOS / native Android codebase
