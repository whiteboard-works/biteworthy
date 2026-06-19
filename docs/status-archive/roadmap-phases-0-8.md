# Roadmap history — Phases 0–8 (shipped)

Archived from `docs/roadmap.md` on 2026-06-19 once every phase had
shipped, to keep the living roadmap focused on what's left. This is the
full record: the per-PR Done list, each phase's scope + the demo it
ended on, and the Discovered follow-ups that were resolved. Read-only.

Subplans with per-task acceptance criteria live in `docs/plans/archive/`.

## Done (per-PR)

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
- ✅ Phase 4.11.0 / 4.11.2-cassette — recorded against Simply Tasty Thai appetizers; ExtractMenuJob integration smoke now real — **Phase 4.11 fully complete**
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
- ✅ Phase 8.3 — Top Picks UI (web): server-score-driven row + "because you like…" lines + Why-these explainer; anonymous unchanged (#311)
- ✅ Phase 8.4 — Top Picks UI (mobile); selector + reason-line moved into filter-engine so web/mobile share one implementation (#312)
- ✅ Phase 8.5a — taste onboarding foundations: tags endpoint (Phase-0 route had no action), reducer taste cycle + payload helpers (#313)
- ✅ Phase 8.5b — taste onboarding UI (web + mobile): "What do you love?" step (cuisine/flavor chips + optional ingredient search, skippable) between strictness and review; ?step=taste standalone "Improve my picks" save (taste-only, can't wipe avoid lists); taste_signal_count on profile_set — **Phase 8 feature-complete: safety filters, taste ranks, end to end**
- ✅ Local-dev + refactor wave — Docker local-dev stack (#315); single-source `API_BASE` web+mobile (#316, #319); BaseController shared pagination / `photo_url_for` / `public_host` (#317, #318); proxyAuthed/relayUpstream web `/api` routes (#320); ResolveStageJob + ResolvePrompt + TimedAnthropicCall ingestion extractions (#321–#323); `docs/vision.md` + `/story` page (#324–#325)
- ✅ Legal remediation — honest privacy/ToS copy + plan (#327); E1–E13: allergen disclaimer + onboarding ack (#328), data-export / account-deletion endpoints (#329, #330), age gate 13+ (#331), visit-history retention job (#332), expiring + redacted share tokens (#333), analytics opt-in + dietary-field stripping (#334), report-a-review + DMCA intake (#335, #337), neutral handle (#336), rack-attack throttling (#340), review edit/delete (#339), public-profile leak test (#341); ToS disclaimers + footer (#343); clickwrap Terms at signup (#344); mobile hosted legal pages (#345); one-way NDA template (#346)

## Phase 0 — Foundation ✅

- [x] Archive 2020 codebase to `_legacy/`
- [x] pnpm + Turborepo monorepo
- [x] Rails 8 API skeleton (config, schema, models, seeds)
- [x] Next.js 15 web skeleton
- [x] Expo mobile skeleton
- [x] Shared TS packages: api-types, filter-engine (with tests),
      ui-tokens, eslint-config
- [x] CI workflow committed
- [x] ADR 0001 capturing every stack pick
- [x] Delivery playbook + status log + phase subplans

**Demo:** all three apps say "hello" against the same Rails API.

## Phase 1 — Schema + auth + admin ✅

Subplan: `docs/plans/archive/phase-1.md`. All 7 tasks merged (#124, #128,
#130, #131, #132, #133, #134) plus the auto-merge policy chore (#129).

**Demo (achieved 2026-04-29):** admin can create a restaurant + 10-item
menu in `/admin` (Phase 1.5); web and mobile call
`GET /api/v1/restaurants/:id/items?profile=…` (Phase 1.7) and items
either show or carry a transparent reason for being hidden.

## Phase 2 — AI ingestion MVP ✅

Subplan: `docs/plans/archive/phase-2.md`. All 9 tasks merged
(#136, #137, #138, #139, #140, #141, #142, #143, #144).

**Demo (achieved 2026-04-30):** end-to-end ingestion pipeline shipped
— web URL/PDF entrypoint OR mobile multi-page camera capture →
ExtractMenuJob (vision) → ResolveIngredients/ResolveTags jobs →
IngestionItems staged → admin verify (Avo) or mobile swipe-verify
→ 80%-accepted threshold flips run + restaurant to :published.
Cost + latency dashboard at `/admin/dashboard` tracks the $0.25/
50-item-menu target. The Phase 4.11.0 cassette later replaced the
mocked-AnthropicClient specs with a real recorded interaction.

## Phase 3 — Dietary filter ✅

Subplan: `docs/plans/archive/phase-3.md`.

- Profile onboarding (6 taps to working filter)
- Curated dietary-profile presets fully wired
- Filtered restaurant page (mobile + web) — `applyProfile` from filter-engine
- Transparency layer: every hidden item shows reason
- One-tap override per item ("show anyway")
- Strict-mode toggle (hides anything not `confidence: confirmed`)
- Shareable filter URLs (encode profile in a token)

**Demo (achieved 2026-04-30):** open the app, pick "Celiac + tree-nut
allergy", scan a real menu, see only the dishes that pass. Hidden
items each say *why*. Tap "show anyway" and it re-appears client-side.
Share a filtered link via `/r/<slug>?p=<token>`.

## Phase 4 — Reviews + accounts ✅

Subplan: `docs/plans/archive/phase-4.md`.

- Per-item reviews (1–5 + text + photo)
- Review moderation queue
- User profile pages
- "My filtered menus" history
- Restaurant claim flow (domain-email verification)
- Suggestion queue UX for community edits

**Demo (achieved 2026-04-30):** a logged-in user reviews a dish from a
restaurant they filtered to; an owner claims that restaurant via
domain-email verification; a contributor suggests a missing-ingredient
fix and the owner accepts it from the queue.

## Phase 4.11 — Per-dish photo extraction ✅

Subplan: `docs/plans/archive/phase-4.11-dish-photos.md`. Pulls each dish
photo out of the source menu page and attaches it to the resulting Item,
so the restaurant page renders the menu with real food photos. Included
the long-deferred Phase 2.3 cassette PR as prerequisite (4.11.0).

**Demo:** open a restaurant page; items that had a photo on the source
menu page render with the cropped photo alongside name + description.

## Phase 5 — Launch infrastructure ✅ (code complete)

Subplan: `docs/plans/archive/phase-5.md`. Every loop-shippable launch
piece is on master; the remaining launch tasks are human-credential-gated
(see `docs/launch-readiness.md`).

- Production deploy wiring (Kamal + Hetzner + Neon per ADR 0007; Fly.io retired)
- Production SMTP (Postmark) + email smoke task
- Production blob storage on Cloudflare R2 + backfill task
- Web deploy wiring: vercel.json + sitemap + cookie domain
- Marketing landing page + waitlist
- SEO city/diet pages at `/durango/[diet]`
- Durango batch ingest task + CSV template
- PostHog analytics abstraction + 9-event taxonomy, wired into both apps
- Privacy/terms/app-store listing templates; press kit + outreach templates

**Demo target:** real users on a Friday night using it to pick where to eat.

## Phase 6 — Anyone-can-scan ingestion ✅

Subplan: `docs/plans/archive/phase-6.md`. Opened the Phase-2 pipeline to
every signed-in user with quotas, a cost ceiling, pg_trgm duplicate
detection, and a trust model where community verification lands
`confidence: suggested` (strict-mode users stay protected until an admin
confirms).

**Demo:** a non-admin account creates a new restaurant, scans its menu,
swipe-verifies, and it goes live — invisible to strict-mode users until
confirmed. A second scanner gets a "did you mean…?" dedup prompt.

## Phase 7 — Close the real-world mobile scan loop ✅

Subplan: `docs/plans/archive/phase-7.md`. Wired the real expo-camera
capture (the Phase 2.6 TODO), replaced the placeholder mobile home screen
with search + a scan CTA, and stitched search-miss → create → capture →
progress → verify → filtered menu into one flow. (Device camera pass
still pending a human phone test; near-me deferred pending expo-location.)

**Demo:** cold-start the app at a restaurant that isn't listed and get
from "Scan a menu" to reading your own filtered menu without leaving the
flow.

## Phase 8 — "Most likely to enjoy" taste ranking ✅

Subplan: `docs/plans/archive/phase-8.md`. Safety filters, taste ranks: new
liked/disliked signal arrays on profiles, a deterministic scoring model
implemented twice (SQL + filter-engine) with a parity fixture, a Top Picks
row on web + mobile, and an optional taste onboarding step.

**Demo:** two users with identical allergies open the same menu and see
the same safe items but different Top Picks, each with a "because you
like…" explainer.

## Resolved Discovered follow-ups

- ~~Wire `jest-expo` preset + `@testing-library/react-native` for mobile,
  AND `@testing-library/react` + jsdom for web~~ — promoted to Next-up
  (web side) after three paused ticks; mobile counterpart followed.
  Surfaced during Phase 3.5; reinforced by Phase 4.11.4's inability to
  ship a JSX render snapshot. Deferred snapshots from 3.2/3.3/3.4/3.5/4.11.4
  to be added retroactively.
- ~~**Auto-merge is completing on red (June 2026).**~~ — resolved
  2026-06-11: required status checks re-applied to master branch
  protection via API (tick #129; contexts in `.github/README.md` §5),
  after #280 restructured both CI workflows to report on every PR. The
  full automation plan lives in `docs/automations-todo.md`.
- ~~**Dependabot bumps Expo-managed native deps past SDK support.**~~ —
  resolved 2026-06-11: ignore rules added in #279; the monthly
  `expo-align.yml` workflow owns these versions now (#283, #292). One last
  over-bump (#276) raced in before the ignores landed; realigned in #292.
- ~~Consolidate web + mobile pure helpers~~ — done in Phase 3.7 (#152). All
  display helpers (`hiddenReasonLabel`, `groupItemsBySection`,
  `applyOverrides`) now live in `@biteworthy/filter-engine`.
- ~~**Mobile jest config: `setupFilesAfterEach` typo in PR #191**~~ — fixed
  in PR #195. The correct Jest 29 key is `setupFilesAfterEnv`; the setup
  file's import path was also dead (removed in @testing-library/react-native
  v13, matchers auto-register as a side-effect import). Both removed.
</content>
