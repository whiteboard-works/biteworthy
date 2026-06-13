# Roadmap

The phase plan. Each phase ends with a real demo. The autonomous
delivery loop reads the **Next up** queue below to pick its next PR;
each entry links to a `docs/plans/phase-N.md` subplan with the gory
details.

## Next up

The loop takes these in order, top-down. `[BLOCKED]` prefix means
"skip; needs a human to clear." See `docs/delivery-playbook.md` for
the merge / review / status rules.

**Phases 6–8** ⭐ The product-vision arc (owner-approved 2026-06-12):
**6** anyone-can-scan ingestion (`docs/plans/phase-6.md`) → **7** close
the real-world mobile scan loop (`docs/plans/phase-7.md`) → **8**
"most likely to enjoy" taste ranking (`docs/plans/phase-8.md`).
Queue below runs top-down; the launch wiring items stay `[BLOCKED]`
at the bottom until credentials drop.

**Phase 5** ⭐ Launch (Durango). Subplan: `docs/plans/phase-5.md`. **Loop work complete** — every code-only Phase-5 PR is on master. The full state-of-the-world checklist for the human is at `docs/launch-readiness.md`.

Test-infra wiring shipped both sides (web in #189, mobile in #191). Mobile ItemRow + Phase 4.11.4 photo snapshot landed in #192. Phase 3.2 onboarding-screen backfill landed in this PR — Phases 3.4 (HiddenReasonChip) and 3.5 (StrictnessToggle) are already covered by `restaurant-screen.render.test.tsx` (#191), and the Phase 3.3 helpers (FilterBadge, SectionBlock) are simple enough to wait for a real bug to motivate them. **No remaining loop-shippable test-infra followups.**

1. **Phase 8.4 — Top Picks UI (mobile)** (`docs/plans/phase-8.md`)
9. **Phase 8.5 — taste onboarding step (web + mobile)**
15. **[BLOCKED] Phase 5.9-wiring — generate binary assets + screenshot routes + EAS submit** (followup to #180). Needs Apple Developer ($99/yr) + Google Play Console ($25 one-time) + lawyer signoff on `/privacy` + `/terms` + designed icon-source.svg.
16. **[BLOCKED] Phase 5.1.1-wiring — CI-driven `kamal deploy` on master push** (followup to #182). Needs first manual `kamal deploy` to prove the manual flow works before CI automation; that needs the Hetzner + Neon + GHCR provisioning per `docs/launch-readiness.md` step 1.

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
- ✅ Phase 5.1.1 — plan: switch API hosting to Kamal + Hetzner + Neon (#181)
- ✅ Phase 5.1.1 — implementation: deploy.yml + .kamal + ADR 0007 (#182) — **API hosting story rewritten; Fly.io retired before live deploy**
- ✅ Phase 5.10 — press kit + waitlist + Durango outreach templates (#183) — **last code-only Phase 5 PR**
- ✅ Launch-readiness checklist + loop pause (#184) — `docs/launch-readiness.md` is the human's linear path from "code complete" to launch.
- ✅ Phase 4.11.0 / 4.11.2-cassette — recorded against Simply Tasty Thai appetizers; ExtractMenuJob integration smoke now real (this PR) — **Phase 4.11 fully complete**
- ✅ Phase 5.8-wiring — posthog-js + posthog-react-native wired into the 9 funnel events (#218) — code side complete; setting the real `*_POSTHOG_KEY` in Vercel/EAS is launch-readiness step 7
- ✅ Phases 6–8 — subplans committed (#296)
- ✅ Phase 6.1 — non-admin ingestion runs + quotas + cost ceiling (#297)
- ✅ Phase 6.1.1 — ingestion hardening: real cost accrual, quota race, upload caps (#298)
- ✅ Phase 6.1.2 — pre-fetch quota check + usage on schema failures (#299)
- ✅ Phase 6.2 — community restaurant creation + pg_trgm dedup (#300)
- ✅ Phase 6.3 — self-verify + suggested-confidence trust model (#301)
- ✅ Phase 6.4 — community-publish moderation visibility (#302)
- ✅ Phase 6.4.1 — moderation gaps: rescan scope, mixed-ai items, run filter (#303)
- ✅ Phase 6.5 — web community scan entrypoint (#304)
- ✅ Phase 6.6 — mobile community scan entrypoint (#305) — **Phase 6 feature-complete: anyone-can-scan on both surfaces**
- ✅ Phase 7.1 — real expo-camera capture via ref (#306)
- ✅ Phase 7.2 — real mobile home screen: search + scan CTA; near-me deferred pending expo-location (#307)
- ✅ Phase 7.3 — scan-to-menu flow stitched: search-miss → prefilled create → capture → stage progress → verify → deep-link to own filtered menu; re-scan entry on the menu screen (#308) — **Phase 7 feature-complete (device camera pass still pending a human phone test)**
- ✅ Phase 8.1 — taste signal schema + profile API: 4 liked/disliked uuid[] columns, disjoint + existence validations, rswag + codegen (#309)
- ✅ Phase 8.2 — taste scoring engine: SQL TasteScoring + TS scoreItem/topPicks, shared parity fixture both suites assert to 4dp, taste_score/taste_reasons on the items endpoint (#310)
- ✅ Phase 8.3 — Top Picks UI (web): server-score-driven row + "because you like…" lines + Why-these explainer; anonymous unchanged (this PR)

**🎉 Phase 5 loop work is complete.** Every loop-shippable launch piece is on master. The remaining queue is entirely human-credential-gated; see `docs/launch-readiness.md` for the linear path from "code complete" to "real users on a Friday night."

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

## Phase 6 — Anyone-can-scan ingestion

Subplan: `docs/plans/phase-6.md`. Opens the Phase-2 pipeline to every
signed-in user with quotas, a cost ceiling, pg_trgm duplicate
detection, and a trust model where community verification lands
`confidence: suggested` (strict-mode users stay protected until an
admin confirms).

**Demo:** a non-admin account creates a new restaurant, scans its
menu, swipe-verifies, and it goes live — invisible to strict-mode
users until confirmed. A second scanner gets a "did you mean…?"
dedup prompt.

## Phase 7 — Close the real-world mobile scan loop

Subplan: `docs/plans/phase-7.md`. Wires the real expo-camera capture
(the Phase 2.6 TODO), replaces the placeholder mobile home screen
with search + near-me + a scan CTA, and stitches search-miss →
create → capture → progress → verify → filtered menu into one flow.

**Demo:** cold-start the app at a restaurant that isn't listed and
get from "Scan a menu" to reading your own filtered menu without
leaving the flow.

## Phase 8 — "Most likely to enjoy" taste ranking

Subplan: `docs/plans/phase-8.md`. Safety filters, taste ranks: new
liked/disliked signal arrays on profiles, a deterministic scoring
model implemented twice (SQL + filter-engine) with a parity fixture,
a Top Picks row on web + mobile, and an optional taste onboarding
step.

**Demo:** two users with identical allergies open the same menu and
see the same safe items but different Top Picks, each with a
"because you like…" explainer.

## Discovered (loop-added followups)

The loop appends here when work surfaces a new task that doesn't
belong in the current phase. Humans triage these into the appropriate
phase or "Next up" queue.

- **Onboarding-chip flake recurred (3rd occurrence)** — the test
  fixed in #199 ("renders a chip per preset once the fetch
  resolves") timed out again on #304's CI runner (suite took 16.5s;
  5s per-test cap). The findByLabelText fix helped locally but slow
  CI runners still trip it. Candidate fixes: bump that test's
  timeout to 15s, or jest.setTimeout for the file. One-line change;
  promote on next paused tick or fold into the next mobile PR.
- **Phase 6.5/6.6 codex P2 followups (web+mobile verify UX)** — from
  #304's review, all reasonable, none blocking: (1) logged-out users
  hit the create step before any 401 redirect — picker should
  redirect like upload does; (2) no edit-before-accept path in the
  web verify list (API supports `edited`; mobile verify has it);
  (3) "did you mean" cards offer other users' DRAFTS as reusable
  targets, which then 403 at scan time — filter candidates to
  published-or-own; (4) web verify polling stops permanently on one
  transient fetch failure — retry with backoff. Also applies partly
  to mobile picker (3). Bundle as Phase 7.0 cleanup PR.
- **Ingestion + restaurant endpoints lack rswag specs** (noted while
  shipping 6.1/6.2). `POST /ingestion_runs`, `PATCH .../items/:id`,
  `POST /restaurants` aren't in `docs/openapi.json`, so api-types
  stays hand-written for them. One PR could rswag the lot + re-run
  codegen. Pre-existing gap (only auth/profile/items were ever
  rswag'd) — surfaced now because Phase 6 keeps touching these
  endpoints.
- ~~Wire `jest-expo` preset + `@testing-library/react-native` for the
  mobile app, AND wire `@testing-library/react` + jsdom for the web
  app~~ — **promoted to Next-up #1 (web side) in tick #94 after three
  paused ticks**. Mobile counterpart will be its own follow-up PR.
  Original note: surfaced during Phase 3.5; reinforced by Phase
  4.11.4's inability to ship a JSX render snapshot for the new
  dish-photo `<Image>` / `<img>` on either side. Once landed,
  retroactively add the deferred snapshots from 3.2 / 3.3 / 3.4 /
  3.5 / 4.11.4 (web RestaurantClient ItemRow + mobile [id].tsx
  ItemRow asserting `photo_url` renders into an `<img>` / `<Image>`
  when set, doesn't render when null).
- ~~**Auto-merge is completing on red (June 2026).**~~ — **resolved
  2026-06-11**: required status checks re-applied to master branch
  protection via API (tick #129; contexts in `.github/README.md` §5),
  after #280 restructured both CI workflows to report on every PR.
  The full automation plan that came out of this incident lives in
  `docs/automations-todo.md`.
- ~~**Dependabot bumps Expo-managed native deps past SDK support.**~~ —
  **resolved 2026-06-11**: ignore rules added in #279; the monthly
  `expo-align.yml` workflow owns these versions now (#283, #292). One
  last over-bump (#276) raced in before the ignores landed; realigned
  in #292.
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
- ~~**Mobile jest config: `setupFilesAfterEach` typo in PR #191**~~ —
  fixed in PR #195 (tick #103, third paused tick). The correct Jest
  29 key is `setupFilesAfterEnv`; further investigation found the
  setup file's import path (`@testing-library/react-native/extend-
  expect`) was removed in v13 anyway, and the package's main entry
  auto-registers matchers as a side-effect import — so the file was
  doubly dead. Both removed.

## What we are explicitly NOT doing in v1

- 14-tier user levels / gamification
- Restaurant-deal coupons
- Reservations / delivery integrations
- Social feed
- A separate native iOS / native Android codebase
