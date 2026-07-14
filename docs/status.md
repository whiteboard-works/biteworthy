# Delivery status log

The autonomous loop's running log. Newest entries on top. One line per
tick or significant event. Format:

```
YYYY-MM-DD HH:MM (UTC) — <summary>
```

The point is breadcrumbs: a tick interrupted at minute 28 should leave
enough here for the next tick (or a human dropping in) to resume
without spelunking GitHub.

Entries from ticks #1–#126 (2026-04-28 → 2026-05-06, Phase 0 through
the Phase 5 pause) are archived in
[`status-archive/2026-04-to-05.md`](status-archive/2026-04-to-05.md).

---

2026-07-14 (post-launch fixes) — content seeding + Durango SEO. Branch
`fix/durango-diet-slugs`.

- **CRITICAL, now fixed — production DB was empty of taxonomy.** The running
  API container (Neon `neondb`, pooler host) had `ingredients=0 tags=0
  dietary_profiles=0 restaurants=0`: `db:seed` never populated the *current*
  database — during the multi-db→single-db churn, seeds ran against a Neon
  database that was later deleted, and `db:prepare` only seeds on fresh
  creation. **Solid Cache masked it** — `/api/v1/ingredients` served stale
  cached JSON, so the endpoints looked healthy while the DB was bare (the
  filter product was actually non-functional). Fixed by running
  `kamal app exec --reuse "bin/rails db:seed"` → **36 tags, 1088 ingredients,
  10 dietary profiles** (idempotent upsert). Verified via direct psql, not the
  cached endpoint. Gotcha: `kamal app exec` runs on ALL roles (web+worker)
  concurrently → the two seed runs raced ("Slug has already been taken"); the
  web run completed fully, so the data is correct. Use a single role for
  one-off data tasks (`--role web` before `app exec`, not after).
- **Durango city created** (empty) via psql INSERT so the `/durango/[diet]`
  SEO pages resolve; they self-heal from the build-time 404 via `revalidate`
  ISR once the API returns 200. Verified vegan/vegetarian/celiac/pescatarian
  now 200.
- **Fixed `DURANGO_DIET_SLUGS` drift** (this PR): `tree-nut-free`,
  `shellfish-free`, `lactose-free`, `low-fodmap` were never seeded and 404'd.
  Replaced with real slugs (`gluten-free`, `dairy-free`, `tree-nut-allergy`,
  `peanut-allergy`); updated the test to guard against the drift.
- **Still open:** real Durango restaurant content (pages show the empty state);
  Mailgun SMTP creds (SMTP_* empty); the Vercel prod deploy needed a manual
  Force-Promote (master merge didn't auto-trigger — verify future pushes).

2026-07-14 (latest) — LAUNCH: DNS cutover complete, API live over HTTPS, web
build fixed. Continuation of the provisioning session below; same branch
`chore/launch-provisioning`.

**Done:**
- **Nameserver flip landed** (user migrated the registrar to the WBW
  Cloudflare account). `bite-worthy.com` NS = cris/janet.ns.cloudflare.com,
  zone active. Verified resolving: `api → 87.99.137.181`, apex + www → Vercel
  edge (216.150.x.x via CNAME flattening).
- **API LIVE over HTTPS:** `https://api.bite-worthy.com/up` → 200 with a valid
  Let's Encrypt cert (issued automatically once DNS resolved). Taxonomy is
  seeded — `/api/v1/ingredients` and `/api/v1/dietary_profiles` return real
  data.
- **Vercel DNS staged in Cloudflare** (both DNS-only, per Vercel's new IP
  range): apex CNAME + www CNAME → `311e341e12f61b6e.vercel-dns-016.com`
  (www is a 308→apex redirect in Vercel). Cloudflare CNAME-flattening lets the
  apex CNAME coexist with the pre-existing Mailgun MX/SPF/DKIM records.
- **Web production build fixed + pushed** (commit d73c1fb): tailwind pinned to
  v3 (v4 broke postcss/config), login+signup `<Suspense>` boundaries, and
  `durango/[diet]` `revalidate=300` + empty-state fallback. `pnpm build` green
  (typecheck + lint + 180 tests).
- **Removed dead `resources :cities` route** — no controller existed, so
  `GET /api/v1/cities` returned 500. The used `/cities/:city_slug/restaurants`
  route stays; spec green on a clean test DB.

**Discovered:** production DB has the taxonomy but NO city/restaurant/menu
content — `db/seeds.rb` seeds taxonomy only; Durango restaurants come from the
ingestion/onboarding flow, not seeds, so `/durango/[diet]` shows the
empty-state fallback until content is loaded. Also: pre-existing **Mailgun**
email records (MX/SPF/DKIM) already on the zone — could serve transactional
email instead of the pending Postmark signup.

**Still manual (user):** SMTP provider (Postmark signup OR wire existing
Mailgun SMTP creds — `SMTP_*` still empty in `.kamal/secrets`); Vercel
production deploy fires on merge to `master`; Apple/Google dev accounts +
D-U-N-S; attorney (L1); DMCA agent; icon-source.svg pick; Anthropic billing.

2026-07-14 (later) — LAUNCH PROVISIONING, interactive (no tick), branch
`chore/launch-provisioning`. Handoff state for the next session:

**Done this session:**
- Hetzner server LIVE: `biteworthy-api`, **cpx21** (not cx22 — the CX/Intel
  line doesn't exist in US DCs; cpx21 = 3 vCPU/4 GB/80 GB, ~$8.5/mo — ADR
  0007 needs this correction), ash-dc1, IP **87.99.137.181**, ubuntu-24.04,
  SSH key `skylar`, root SSH verified, Docker bootstrapped via
  `kamal server bootstrap`.
- `apps/api/.kamal/secrets` built (gitignored): DATABASE_URL rewritten to
  Neon **pooler** host + sslmode=require (user's `.env` had the unpooled
  one), fresh DEVISE_JWT_SECRET_KEY, RAILS_MASTER_KEY from newly generated
  credentials (`config/master.key` + committed `credentials.yml.enc` —
  repo previously had NO credentials at all), ANTHROPIC/ADMIN from `.env`,
  KAMAL_REGISTRY_PASSWORD = fresh GitHub classic PAT
  `biteworthy-kamal-ghcr-laptop` (90d, write:packages, owner @wbwSoftware;
  `docker login ghcr.io` verified). SMTP_*/R2_* still EMPTY placeholders.
- `config/deploy.yml`: real IP in both roles; removed invalid `hooks:` key
  (Kamal 2 auto-discovers `.kamal/hooks/`; the key errors as
  "unknown key: hooks").
- Cloudflare: bite-worthy.com zone added to the WBW account
  (14eec3b118e3baabc516aac5d7ae869c) — **PENDING nameserver flip** (see
  manual items). A record `api → 87.99.137.181` (DNS only) already in the
  new zone. R2 bucket **biteworthy-blobs** created (billing already
  enabled) + Account API token `biteworthy-api-storage` (Object R&W,
  bucket-scoped) — R2_* filled in `.kamal/secrets` and deployed.
- **Worker was NOT healthy after bug (4)** — it crash-looped on
  `solid_queue_recurring_tasks does not exist`. Root cause: the multi-db
  database.yml never worked — ENV["DATABASE_URL"]'s database name
  overrides each entry's `database:` key, so primary/cache/queue/cable
  all resolved to the same Neon db while the solid_* tables existed
  nowhere (the repo's queue/cache/cable schema files were empty
  version-0 stubs; solid_queue:install had never completed). Fixed by
  flattening to a SINGLE database: real solid_queue/solid_cache tables
  added to the primary schema via migration
  `20260714120000_create_solid_queue_and_solid_cache_tables`, installers'
  config/queue.yml + cache.yml committed, connects_to dropped, unused
  ActionCable switched to async. **Verified live: Solid Queue
  supervisor/worker/dispatcher/scheduler all running, BOTH recurring
  tasks registered (purge_orphaned_restaurant_visits preserved after the
  installer clobbered recurring.yml — restored), Rails.cache round-trip
  works.** Deleted the three empty per-db Neon databases this session
  briefly created.
- **Vercel:** project `biteworthy-web` imported (team Skylar,
  whiteboard-works/biteworthy, root apps/web, Next.js preset) with
  NEXT_PUBLIC_API_BASE / COOKIE_DOMAIN / SITE_URL / POSTHOG_KEY set for
  Production+Preview; first deployment building at handoff. Custom
  domains bite-worthy.com + www still to add after build.
- **PostHog:** the WBW Cross-Product project (id 370116) lives in the
  PostHog account the browser is logged into; project token
  `phc_tstSvpFjyUwgb8wD9rbL97SvgBgQe8oUWFGubrWTVavZ` (public client
  token) — used for NEXT_PUBLIC_POSTHOG_KEY, same value for
  EXPO_PUBLIC_POSTHOG_KEY at EAS time.
- Attorney engagement email + legal review packet + 3 icon-source.svg
  drafts delivered to the user as files (Gmail connector is read-only;
  draft couldn't be placed directly).
- **DEPLOYED AND HEALTHY.** `kamal deploy` succeeded after a four-bug
  chain, each fixed + committed on this branch: (1) `hooks:` is not a
  valid Kamal 2 config key; (2) Dockerfile chown failed on dockerignored
  `log/` (mkdir -p first); (3) the pre-deploy hook ran `kamal app exec`
  before any container existed — removed, entrypoint db:prepare +
  healthcheck gate cutover instead; (4) **the web role needs
  `cmd: ./bin/rails server`** — the Dockerfile has ENTRYPOINT but no CMD,
  so the container execd nothing and exited 0 silently (empty logs,
  failed healthcheck). Web + worker both healthy on the box;
  `deploy_timeout: 300` added for cold boots. db:prepare ran clean against
  Neon (~3s). `kamal smoke` passes DB-side ("no published restaurant" =
  correct pre-seed state) and fails ONLY on public DNS resolution —
  expected until the NS flip. External probe:
  `curl --resolve api.bite-worthy.com:80:87.99.137.181 http://api.bite-worthy.com/up`
  → 301 to https (proxy routing works; TLS cert issues itself after DNS).
- `apps/mobile/.env.example`: documented previously-missing
  `EXPO_PUBLIC_WEB_BASE` (share links break to localhost without it).

**Next steps (in order):** (1) confirm `kamal deploy` completed →
`kamal app exec "bin/rails biteworthy:production:smoke EXIT_CODE=1"`;
(2) after NS flip lands, `curl https://api.bite-worthy.com/up` (Let's
Encrypt cert issues on first request); (3) R2: create Object-R&W API
token for biteworthy-blobs, fill R2_* in `.kamal/secrets`
(R2_ENDPOINT = https://14eec3b118e3baabc516aac5d7ae869c.r2.cloudflarestorage.com),
redeploy; (4) Postmark + Vercel + PostHog wiring (accounts may not exist
yet — account creation is user-only); (5) icon SVG drafts, attorney email
draft, cassette, seed. Gotcha: `kamal env push` does NOT exist in Kamal 2
(docs are stale) — secrets ship with `kamal deploy`.

**Manual items outstanding (user):** flip bite-worthy.com nameservers to
cris/janet.ns.cloudflare.com in whichever Cloudflare account currently
serves malcolm/paloma (registrar = Cloudflare; zone wasn't visible to the
info@whiteboardworks login); Anthropic billing?; Postmark/Vercel/PostHog
signups; Apple/Google dev accounts + individual-vs-org (D-U-N-S) decision;
attorney engagement (L1); DMCA agent ($6); icon-source.svg approval.

2026-07-14 — planning (interactive, no tick). Added `docs/launch-plan.md`
(two-track launch: manual Track A critical path + loop-shippable Track B
lower-the-gate + QR program) and `docs/plans/six-month-plan.md` (the
"how do we win, not just launch" reversal — three steelman-resolved
decisions on sequencing/positioning/trust, tasks split [MANUAL]/[CODE]
across 6 months, gated on the strategy §5 canaries). No code changed yet;
recommended first build = the P0 safety guardrails (filter-engine↔SQL
parity, array-sync invariant, adversarial hidden-allergen test).

2026-06-14 — post-loop interactive work (no tick number; the cron loop
stayed paused). Two workstreams landed on master after tick #147, neither
of which had a status entry until now:
- **Local-dev + refactor wave (#315–#325).** Full Docker local-dev stack
  (API + Solid Queue worker + Postgres, `compose.yaml`, see
  `docs/local-dev.md`) — #315. Then a dedup pass with no behavior change:
  single-source `API_BASE` on web + mobile (#316, #319), BaseController
  shared pagination / `photo_url_for` / `public_host` (#317, #318),
  ResolveStageJob + ResolvePrompt + TimedAnthropicCall extracted for the
  ingestion pipeline (#321–#323), proxyAuthed/relayUpstream for web
  `/api` routes (#320). Plus `docs/vision.md` + the user-facing `/story`
  page (#324–#325).
- **Legal remediation (#327–#346).** Honest privacy/ToS copy + plan
  (Phase 1, #327), then E1–E13 engineering: in-app allergen disclaimer
  + onboarding acknowledgment (#328), personal-data export / account
  deletion endpoints (#329, #330), age gate 13+ (#331), visit-history
  retention backstop job (#332), expiring + log-redacted share tokens
  (#333), analytics opt-in + dietary-field stripping (#334),
  report-a-review + DMCA intake (#335, #337), neutral default handle
  (#336), rack-attack throttling (#340), in-app review edit/delete
  (#339), public-profile leak test (#341). Then ToS disclaimers + footer
  (#343), clickwrap Terms acceptance at signup (#344), mobile signup
  opening hosted legal pages (#345), one-way NDA template (#346).
  Follow-ups tracked in `docs/plans/legal-remediation-followups.md`
  (F1–F6 + L1–L5).
Next: L1–L5 launch gates (remove DRAFT banners, lawyer sign-off) +
the human-credential-gated launch wiring — see `docs/launch-readiness.md`.

2026-06-13 05:30 — tick #147. **Phase 8.5b shipped — taste onboarding
UI (web + mobile). Phase 8 feature-complete.** JS-only PR (no apps/api
changes → ci-api/rspec/brakeman/openapi untouched).
- New "What do you love?" step between strictness and review on both
  surfaces (now 5 steps): cuisine/flavor tag chips from
  GET /api/v1/tags?families=cuisine,flavor that cycle neutral → liked
  → disliked → neutral on tap, plus an optional favorite-ingredient
  search. Skippable — taste is soft, safety is not.
- Standalone "Improve my picks": `?step=taste` (web useSearchParams,
  mobile useLocalSearchParams) opens the step alone and saves via the
  taste-only saveTaste/toTastePayload, so refining picks can NEVER
  wipe the avoid lists. Web page wrapped in <Suspense> (Next 15
  useSearchParams prod-build requirement). Entry link added to the
  TopPicksRow header on both surfaces.
- Contract: optional taste_signal_count on profile_set (analytics
  EventPropsMap + docs/analytics.md, both updated same PR; no rename).
  fetchTags + saveTaste + SaveTastePayload added to both onboarding
  libs; SaveProfilePayload extended with the 4 optional taste arrays.
- Tests: web 153 (+9: fetchTags/saveTaste lib shapes + taste-step page
  render incl. standalone-save footgun guard + improve-picks link),
  mobile 120 (+2: taste step in the of-5 flow + chip cycle); existing
  of-4 flow assertions migrated to of-5. typecheck/lint green across
  the workspace.
Next: Phase 8 done — remaining queue is human-credential-gated launch
wiring (see docs/launch-readiness.md).

2026-06-13 03:15 — tick #146. **Phase 8.5a shipped — taste onboarding
foundations** (session wrapping on user request; 8.5b = the UI half,
queued at the top of Next-up with a full handoff note).
- GET /api/v1/tags implemented — third Phase-0 route that existed
  with no controller (after restaurants index). Public,
  ?families=cuisine,flavor whitelist filter, limit cap 200. +4 specs
  (incl. injection-shaped family names ignored). rspec 465/465.
- onboarding-reducer: 4 taste arrays in DraftProfile,
  CYCLE_TASTE_TAG / CYCLE_TASTE_INGREDIENT (neutral → liked →
  disliked → neutral, one tap target covers both polarities),
  toProfilePayload now carries the four arrays (empty when step
  skipped), NEW toTastePayload for the standalone "Improve my picks"
  save — taste-fields-only PATCH so it can NEVER wipe the avoid
  lists (wholesale-replace footgun, caught in design). +3 specs,
  filter-engine 171/171; web/mobile suites untouched and green.
Next: Phase 8.5b taste onboarding UI (web + mobile) — see Next-up
for the precise remaining scope.

2026-06-13 02:40 — tick #145. **Phase 8.4 shipped — Top Picks UI
(mobile).** #311 (8.3) auto-merged on green. This PR:
- filter-engine: topPicksFromScores + tasteReasonLine + TasteReason/
  ScoredWireItem promoted from the web app into the shared package
  (one selector, web + mobile can't drift); MIN_POSITIVE_PICKS /
  TOP_PICKS_COUNT constants replace magic numbers in topPicks too.
- Web TopPicksRow now imports the shared helpers (deletes its local
  copies; component + tests unchanged otherwise — 144/144 still).
- Mobile: _TopPicksRow horizontal card strip (photo, name, "Because
  you like…" line, Why-these explainer with the taste≠safety copy)
  wired above the menu sections in restaurants/[id]; rawItems state
  added beside sections, same as web. Cards push /items/:id.
  taste_score/taste_reasons added to the mobile RestaurantItem type.
- Tests: +24 vitest filter-engine (163), +5 mobile jest (118):
  thresholds, anonymous null-score no-op, hidden exclusion,
  tie-breaks, reason-line shapes, card navigation, explainer.
Next: Phase 8.5 taste onboarding step (web + mobile) — closes
Phase 8.

2026-06-13 02:05 — tick #144. **Phase 8.3 shipped — Top Picks UI
(web).** #310 (8.2) auto-merged on green. This PR (web-only):
- New TopPicksRow above the menu sections: horizontal cards (photo,
  name, "Because you like Spicy & Basil" line from taste_reasons),
  "Why these?" explainer whose copy explicitly says everything below
  passed the dietary filter (taste ≠ safety rule).
- Selection uses the SERVER's Phase 8.2 scores — no client
  recompute: top 5 visible score>0, nothing under 3 positive picks.
  Anonymous/zero-signal payloads carry null scores → row absent,
  page byte-identical to pre-8.3.
- RestaurantClient keeps rawItems state alongside sections so picks
  survive strictness refetches. taste_score/taste_reasons added to
  the web RestaurantItem type.
- Deviation noted: plan card lists "price" — the items endpoint has
  no price field (prices live only on ingestion payloads), so cards
  ship without it; surfaced rather than silently extending the API.
- +11 vitest (web 144/144): thresholds, null-score anonymous, hidden
  exclusion, sort ties, reason-line shapes, explainer toggle, links.
Next: Phase 8.4 Top Picks UI (mobile).

2026-06-13 01:30 — tick #143. **Phase 8.2 shipped — taste scoring
engine, SQL + TS in one PR.** #309 (8.1) auto-merged on green.
- New TasteScoring service: one sanitized SQL query per request
  (unnest/array_agg intersections, MAX(popularity) window,
  AVG(visible reviews) join); weights live in WEIGHTS and reach the
  SQL through placeholders so the constant and the expression can't
  drift. Brakeman-clean (first draft interpolated quoted values —
  flagged it; rewrote with sanitize_sql_array).
- Items endpoint: taste_score + taste_reasons ("because you like…"
  ids + names) per item; sort flips to score DESC, popularity DESC,
  name ASC only when the signed-in caller's profile has signals
  (presets/tokens/anonymous = untouched legacy payload, score null).
  Taste never hides: negative-score items stay visible. Avoid-listed
  ids subtracted from signals before scoring (filter wins).
- filter-engine: scoreItem/topPicks/hasTasteSignals + TASTE_WEIGHTS.
  topPicks: top-5 visible score>0, none under 3 picks; hidden items
  still normalize popularity (matches the SQL window).
- Parity contract: shared fixture (4 items × 2 profiles incl.
  avoid-overlap) asserted to 4dp by BOTH vitest and rspec.
- +21 vitest (139 total), +16 rspec (461 total: 10 parity/scoping +
  6 endpoint). rswag items schema + openapi-export + codegen in-PR.
Next: Phase 8.3 Top Picks UI (web).

2026-06-13 00:35 — tick #142. **Phase 8.1 shipped — taste signal
schema + profile API.** #308 (7.3) auto-merged on green. This PR:
- Migration: liked/disliked_ingredient_ids + liked/disliked_tag_ids
  uuid[] (default {}) on user_profiles; no GIN (read-side only).
- UserProfile validations: liked∩disliked = 422 ("loved AND hated"
  silently cancels in scoring — fail loud), unknown UUIDs = 422.
  Avoid-overlap is deliberately ALLOWED (filter wins; scoring
  ignores it in 8.2). NOTE: the plan said "same validation pattern
  as the avoid arrays" but the avoid arrays have NO existence
  validation — taste arrays are stricter than avoid; flagged in the
  PR rather than silently matching the looser precedent.
- GET/PATCH /api/v1/profile round-trips the four arrays (wholesale
  replacement, same as avoid). rswag schema + body params updated,
  openapi-export + api-types codegen in-PR.
- +5 request specs (defaults, round-trip, both-lists 422, unknown
  UUID 422, avoid-overlap OK). rspec 445/445; brakeman clean; JS
  typecheck/lint/test green.
Next: Phase 8.2 taste scoring engine (SQL + filter-engine, one PR).

2026-06-12 22:55 — tick #141. **Phase 7.3 shipped — scan-to-menu flow
stitched end-to-end. PHASE 7 FEATURE-COMPLETE.** #307 (7.2)
auto-merged on green. This PR (all mobile):
- Home search-miss is now a CTA carrying the typed name →
  /ingest?name=… prefills the new-restaurant form; result rows pass
  ?from=search.
- /ingest accepts ?restaurantId&restaurantName (skips the picker) —
  used by the new "📷 Menu changed? Re-scan" entry on the restaurant
  screen (server-side Phase 6.2 ownership rules unchanged).
- Verify screen: pipeline stages render human copy ("Reading the
  menu…" / "Matching ingredients & tags…"); finishing the deck
  refetches the run and deep-links to /restaurants/:id?from=scan —
  celebratory copy when the 80% auto-publish tripped, threshold
  explainer otherwise; "nothing to verify" also links out.
- restaurant_tap now uses the carried ?from (search | scan; default
  direct) — existing event, no taxonomy change.
- Tests: +2 ingest entry-point specs, new verify.render.test.tsx
  (4 specs: stage copy, published deep-link, sub-threshold link,
  nothing-to-verify), +2 full-screen restaurant specs (re-scan
  route, from-param tracking), home specs updated. Mobile jest
  113/113 (+11); typecheck + lint green. No API changes.
Next: Phase 8.1 taste signal schema + profile API.

2026-06-12 19:05 — tick #140. **Phase 7.2 shipped — real mobile home
screen.** The Phase-0 "Pre-MVP" placeholder is gone: debounced
(300ms) restaurant search → tap into the filtered menu, scan CTA →
/ingest, profile link → /onboarding; search-miss copy nudges toward
scanning. API: implemented the GET /api/v1/restaurants index that
was routed since Phase 0 but had no action (500'd) — published
scope, ?q= ILIKE with sanitize_sql_like, 25-row cap, summary
serializer incl. lat/lng for the deferred near-me sort
(expo-location followup). +4 request specs (440 examples green),
+3 lib specs, +5 home.render specs (mobile jest 102/102); typecheck,
lint, brakeman all green. #306 (7.1) auto-merged on green while this
was in flight; branch rebased onto it. Next: Phase 7.3 stitch the
scan-to-menu flow end-to-end.

2026-06-12 12:10 — tick #139. **Phase 7.1 shipped — real camera
capture.** Also logging tick #138 retroactively (its status entry
was deferred to dodge a same-line squash conflict with #304):
- Tick #138 / PR #305: **Phase 6.6 mobile community scan flow** —
  RestaurantPicker ahead of capture (create + did-you-mean rows +
  force), manual UUID fallback, upload routes into swipe-verify,
  friendlyScanError copy. mobile jest 94/94 (+12). **PHASE 6
  COMPLETE — anyone-can-scan works end to end on web + mobile.**
- Tick #139 / this PR: **Phase 7.1** — the Phase 2.6 mock-URI
  capture is now real: CameraView ref + takePictureAsync
  (quality 0.7 keeps pages under the 10 MB cap), capturing busy
  state, permission rationale copy, and hard-denial
  (canAskAgain: false) deep-links to system settings via
  Linking.openSettings. Camera mock upgraded to a forwardRef
  exposing takePictureAsync. mobile jest 97/97 (+3); typecheck +
  lint green. Caveat (honest): verified in jest with the camera
  module mocked — real-device capture still needs a human phone
  test, noted in the PR.
- #304 (6.5) merged after a re-run: its CI failure was the KNOWN
  onboarding flake ("renders a chip per preset", 5s timeout, third
  occurrence incl. pre-fix) — recurrence noted in Discovered.
Next: Phase 7.2 real mobile home screen.

2026-06-12 11:40 — tick #137. **Phase 6.5 shipped — web community
scan entrypoint.** #303 (6.4.1) merged. This PR (web):
- 4 new Next proxies: POST /api/restaurants, GET run, GET run items,
  PATCH item decision (cookie-JWT pattern from Phase 4.1).
- lib/ingestion.ts: createRestaurant (409 → typed duplicates
  result), fetchRun/fetchRunItems/decideRunItem,
  friendlyIngestionError (429 quota / 503 budget / 403 foreign-draft
  → human copy).
- /ingest reworked into the 2-step community flow:
  NewRestaurantPicker (create + "did you mean?" cards + force) →
  URL/PDF upload → push to NEW /ingest/verify/[runId] page: polls
  pipeline status (3s), then VerifyItemRow accept/reject list with
  the 80%-threshold progress line + published banner linking to the
  restaurant page.
- Tests: +9 lib (dedupe/force/error mapping), +8 RTL (picker cards,
  force resubmit, verify row wiring/badge/error).
War story: vitest 4 flags rejected mock results as unhandled iff
the mock was cleared in a beforeEach — empirically isolated;
per-test impls + last-called assertions instead (commented in both
test files). Also the known Next typedRoutes dynamic-push cast
(#274 precedent). web vitest 133/133; typecheck 10/10; lint 6/6.
Roadmap: 6.1–6.5 ticked into Done. Cities note: no cities index
endpoint exists (Phase-0 stub route), so the picker takes a city
slug defaulting to durango — fine for the launch market. Next:
Phase 6.6 mobile entrypoint.

2026-06-12 11:10 — tick #136. **Phase 6.4.1 — three codex P2s from
#302 fixed forward.** (1) community_published scope now also catches
seeded restaurants that received a community RE-scan (EXISTS on
suggested items, not just created_by). (2) confirm-all no longer
graduates an item whose ai-suggested joins remain — item.confidence
only flips when EVERY association is confirmed (strict mode keys
off item.confidence). (3) New Avo CommunityRuns filter on the
ingestion-runs resource (runs by non-admin users). rspec 436/436
(+1 net). Next: Phase 6.5 web community scan entrypoint.

2026-06-12 10:55 — tick #135. **Phase 6.4 shipped — moderation
visibility.** #301 (6.3) merged, zero codex findings. Loop cadence
shortened to 15 min by owner. This PR:
- `Restaurant.community_published` scope + Avo boolean filter on the
  restaurants resource (+ created_by_user fields).
- `Restaurant#confirm_community_associations!` + Avo bulk action
  "Confirm community menu → strict-mode visible": flips
  suggested/human joins + item confidence to confirmed via
  update_all (id arrays untouched — only ids sync via callbacks).
  Deliberately skips source:ai rows — admin endorses the human
  verifier, not the model. Returns counts for the admin message.
- /admin/dashboard: "Community ingestion (today, UTC)" card —
  community run count (non-admin users) + spend vs ceiling using
  EXACTLY the same UTC-day window the 6.1 ceiling enforces; warns
  at ≥80%.
War story: endless-range-at-end-of-line Ruby parse trap — `x = t..`
consumed the next line as the range end → PG DatetimeFieldOverflow.
Parenthesized + commented. rspec 435/435 (+7); brakeman 0.
Next: Phase 6.5 web community scan entrypoint.

2026-06-12 10:20 — tick #134. **Phase 6.3 shipped — community
self-verify + suggested-confidence trust model.** #300 (6.2) merged
with zero codex findings. This PR:
- IngestionItems endpoints widened from admin-only to
  creator-or-admin (`ensure_run_access!`); ownerless runs stay
  admin-only; strangers 403.
- `IngestionItem#promote!(decided_by:)` — admin or legacy no-arg
  call sites (Avo is admin-gated) promote `confirmed`; a community
  scanner verifying their own run promotes `suggested` on the Item
  AND every ItemIngredient/ItemTag join (source stays `human`).
- End-to-end spec proves the safety contract: a community-promoted
  item is hidden under `?strictness=strict` with reason
  `unconfirmed_strict` and visible under balanced — strict-mode
  users never see unconfirmed community data.
rspec 428/428 (+5); brakeman 0. maybe_publish! unchanged (80%
threshold now reachable by community runs — that's the feature).
Next: Phase 6.4 moderation visibility (Avo scope + confirm-all +
dashboard counters).

2026-06-12 03:45 — tick #133 (part 2). **Phase 6.2 shipped —
community restaurant creation + dedup.** #299 (6.1.2) merged.
- New migration: `restaurants.created_by_user_id` (nullable FK).
- `POST /api/v1/restaurants` (authenticated): name + city_slug +
  optional street/postal → draft restaurant recording creator;
  unique slug via parameterize + numeric suffix.
- Dedup guard: pg_trgm `similarity(name, ?) > 0.45` within the same
  city → 409 `possible_duplicate` + up to 5 candidates (id/slug/
  name/status/street); `force: true` overrides. Threshold calibrated
  against live pg_trgm scores: true variants 0.50–0.65, different
  restaurants ≤0.42 ("Durango Diner"/"Durango Bagel").
- Ingestion ownership rule: non-admins may only scan drafts they
  created or published restaurants; foreign drafts 403.
rspec 423/423 (+13); brakeman 0. Deviation from subplan, surfaced
honestly: no rswag spec for the new endpoint — NONE of the
restaurant/ingestion endpoints were ever rswag'd, so openapi/codegen
doesn't change; added a Discovered entry to rswag the lot in one PR.
Next: Phase 6.3 self-verify + community-trust promotion.

2026-06-12 03:05 — tick #133 (part 1). **Phase 6.1.2 — two codex P2s
from #298 fixed forward.** (1) Over-quota callers could still force
an outbound URL fetch: a cheap unlocked limits pre-check now runs
before UrlFetcher; the authoritative check still re-runs under the
advisory lock. (2) Billed 200s that failed schema validation never
accrued usage: all three jobs now record_api_usage! in the
ValidationError rescue before fail!. rspec 410/410 (+2). Part 2 of
this tick: Phase 6.2.

2026-06-12 02:35 — tick #132. **Phase 6.1.1 — community ingestion
hardened per codex review of #297.** All three codex findings were
real and are fixed forward:
- **P1 (cost ceiling read a column nothing wrote):** confirmed —
  no job ever wrote `api_cost_cents`. AnthropicClient now exposes
  `last_usage`; new `Ingestion::UsageCost` prices it (sonnet-4-6
  rate card, cache-read 0.1x / cache-write 1.25x, ceil per call so
  sub-cent calls can't leak the ceiling); all three pipeline jobs
  call the new `IngestionRun#record_api_usage!` (cost + cached/
  uncached token columns + model stamp). The Phase 2.9 dashboard
  starts showing real numbers too.
- **P2 (quota TOCTOU race):** quota check + INSERT now serialized
  per user via `pg_advisory_xact_lock(hashtext(user_id))`; admins
  skip the lock. URL fetch happens BEFORE the lock so a slow
  upstream can't hold a DB transaction open.
- **P2 (unbounded multipart uploads):** per-run caps — max files
  (`INGESTION_MAX_INPUT_FILES`, 10), per-file bytes
  (`INGESTION_MAX_INPUT_FILE_BYTES`, 10 MB = UrlFetcher's cap),
  content-type allowlist (jpeg/png/heic/heif/webp/pdf). Applies to
  admins too.
rspec 408/408 (+14); brakeman 0. Next: Phase 6.2 community
restaurant creation + pg_trgm dedup.

2026-06-12 02:00 — tick #131. **Phase 6.1 shipped — anyone can create
ingestion runs.** Plan PR #296 merged. This PR drops `ensure_admin!`
from POST /api/v1/ingestion_runs and adds the community guardrails:
per-user rolling-24h quota (`INGESTION_RUNS_PER_USER_PER_DAY`,
default 5 → 429 `quota_exceeded`) + global daily spend ceiling over
`api_cost_cents` (`INGESTION_DAILY_COST_CEILING_CENTS`, default
$20 → 503 `cost_ceiling_reached`); admins bypass both. Both vars
documented in `apps/api/.env.example`. The non-admin-403 spec became
a non-admin-201 spec; 7 new limit specs (quota boundary, rolling
window, per-user isolation, prior-day spend ignored, admin bypasses).
rspec 394/394; brakeman 0 warnings. Note: ingestion_runs has no
rswag spec (pre-existing gap — openapi.json never covered it), so no
codegen delta. Next: Phase 6.2 community restaurant creation +
pg_trgm dedup.

2026-06-12 00:05 — tick #130 (interactive session, loop restarted).
**Owner approved the product-vision arc; Phases 6–8 planned and
queued.** Owner restated the BIG goal (anyone scans any menu → full
import incl. ingredients/prices/photos → personalized "most likely
to enjoy" view) and greenlit an overnight 30-min loop to ship it.
Gap analysis: pipeline/extraction/filtering largely built; gaps are
(A) ingestion is admin-only, (B) no taste ranking — only avoid-list
hiding, (C) mobile camera ref TODO + placeholder home screen, (D)
nothing deployed (human-gated). This PR commits the plan:
`docs/plans/phase-6.md` (anyone-can-scan: quotas, cost ceiling,
community restaurant create + pg_trgm dedup, self-verify with
suggested-confidence trust model, moderation visibility, web+mobile
entrypoints), `docs/plans/phase-7.md` (camera wiring, real home
screen, end-to-end scan flow), `docs/plans/phase-8.md` (taste
signals schema, SQL+TS scoring parity, Top Picks UI, taste
onboarding) + roadmap Next-up queue (14 unblocked items, launch
wiring stays [BLOCKED] at bottom). Next: Phase 6.1.

2026-06-11 23:29 — tick #129 (interactive session). **Automation
hardening shipped; branch protection enforced.** Owner asked for the
longterm-development automations; plan written to
`docs/automations-todo.md` (#277), then items 1-6 shipped via five
parallel subagent PRs, all merged:
- #280 ci-js/ci-api report on every PR (path filters moved inside via
  a `changes` job); Brakeman now blocking; codegen drift check prints
  fix commands on failure.
- #278 nightly full-suite run against master + failure issue
  (`ci-nightly` label, mentions @shadoath).
- #281 migration guard (fails PRs editing shipped migrations).
- #279 dependabot ignores for Expo-managed packages (+ expo group
  removed).
- #283 monthly `expo-align.yml` (expo install --fix → verify → PR).
Then: **required status checks applied to master branch protection
via API** (typecheck · lint · test / rspec · brakeman · rubocop /
javascript-typescript / ruby; strict off, admins not enforced) —
verified blocking red dependabot PRs immediately.
War story in between: expo-group bump #276 auto-merged minutes before
#279's ignores landed and re-broke mobile (react-native 0.86 drops
the jest preset jest-expo needs). First dispatched expo-align run
caught the react-test-renderer mismatch in its test gate exactly as
designed but couldn't fix it; #292 realigned the deps to SDK 56 and
taught the workflow to sync react-test-renderer after --fix.
Discovered en route: auto-merged PRs never trigger master-push CI
(merge attributed to GITHUB_TOKEN, events suppressed) — the nightly
run is the only thing exercising master directly.
Remaining TODO items are launch-blocked (P2) or human-decision (P3);
see docs/automations-todo.md.

2026-06-11 23:05 — tick #128 (interactive session). **Master CI was
red; restored green.** Tick #127's docs PR (#273) failed both CI
workflows — the failures predated it. The June dependabot wave
(#227-#272, ~45 PRs) auto-merged with required checks apparently not
enforced on the new org, accumulating four JS breaks and two API
breaks. Fixes shipped as two PRs:
- #274 (ci-js): posthog-react-native 4.45 JsonType cast in the mobile
  adapter; reanimated pinned back to Expo 56's bundled 4.3.1 + missing
  react-native-worklets@0.8.3 peer added; jest-expo → ~56.0.4 with
  jest/@types/jest pinned to 29 (jest-expo is built on jest-29
  internals; jest 30's runtime crashed its environment);
  react-test-renderer 19.2.6 added to match react exactly; `as Route`
  casts for Next typedRoutes on login/signup. Verified: typecheck
  10/10, lint 6/6, test 8/8 (mobile 82/82), codegen:check clean.
- #275 (ci-api): image_processing 2.0 dropped mini_magick from the
  dependency tree but Ingestion::DishPhotoCropper requires it —
  declared explicitly (~> 5.3). Also fixed 3 ingestion_runs specs that
  were red since #223: the SSRF guard resolves DNS, WebMock doesn't —
  stubbed Resolv for the spec host. Verified: rspec 387/0.
Process flags for the human (also in roadmap Discovered): re-enable
required checks on master branch protection; stop dependabot from
bumping Expo-managed native deps past the SDK's bundled versions.

2026-06-11 22:13 — tick #127 (interactive session, not the cron loop).
**Docs sync after ~5 weeks of drift.** Since tick #126, master advanced
through #218-#225 without status/roadmap updates:
- #218 shipped Phase 5.8-wiring (posthog-js + posthog-react-native →
  9 funnel events) — the roadmap still listed it as BLOCKED Next-up #1.
  Ticked it into Done; launch-readiness step 7 now shows only the
  human key-setting steps.
- #221 thai-menu test fixtures; #222 .env.example docs; #223 SSRF +
  CSRF fixes; #224 security dep bumps; #225 compose.yaml for local
  Postgres.
This PR also refreshes CLAUDE.md + all READMEs against shipped
reality (Phase 1.6 codegen is live, packages/analytics exists, local
Postgres via compose.yaml, ci-api installs ImageMagick) and finishes
the Fly.io → Kamal/Hetzner reference sweep the owner confirmed
("Kamal Hetzner is the new standard"): apps/api README email/blob
sections, production.rb + email_smoke.rb comments, web .env.example.
Queue state: both remaining Next-up items (5.9-wiring, 5.1.1-wiring)
stay credential-gated; loop remains paused.

