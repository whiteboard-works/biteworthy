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

2026-04-30 23:11 — tick #89. **Loop pauses for credentials.** PR #183
(Phase 5.10) merged at 22:51 UTC. Anthropic cap clears in ~49 min;
the next tick can attempt the cassette retry but THIS tick is too
early. Read the Next-up queue: every remaining item is either
`[BLOCKED]` (cassette) or implicitly gated on a human credential
drop (PostHog, Apple/Google, manual `kamal deploy`). Per
delivery-playbook §7 stop conditions, this is the right place to
pause + ping. **Phase 5 status: every loop-shippable launch piece
is on master**. Shipped one artifact this tick — a
`docs/launch-readiness.md` checklist organized by what each
human action unlocks (provision Kamal+Hetzner+Neon → wire
SMTP/R2 → provision Vercel → record cassette → seed Durango →
PostHog → App Stores → press outreach). The doc gives the human
a clear linear path from "code complete" to "real users on a
Friday night." After this PR merges, the next 30-min cron tick
should land just after 00:00 UTC and attempt the cassette retry
automatically. If still capped or 4xx, the loop will pause again
and ping. Roadmap unchanged (no new code shipped); no test
deltas (rspec 377/0/1, web vitest 99/99). @shadoath pinged in
the PR body for credential-drop coordination.

2026-04-30 22:50 — tick #88. PR #182 (Phase 5.1.1 Kamal+Hetzner+Neon
migration) merged at 22:23 UTC. Anthropic still capped (~1.2h to
reset); cassette PR stays BLOCKED. Picked the next unblocked
item: **Phase 5.10 — press kit + waitlist + Durango outreach** —
the last code-only Phase-5 PR. Shipped:
- **Waitlist** (API): `create_waitlist_signups` migration with
  citext email + unique idx; WaitlistSignup model with lenient
  EMAIL_REGEX + source allowlist; WaitlistMailer.confirm via the
  Phase 5.2 SMTP pipeline; POST /api/v1/waitlist_signups
  (anonymous, 200 on new+duplicate, 422 on malformed email). 12
  specs (7 model + 5 request) covering normalize, citext dedup,
  source allowlist, controller idempotence, mailer fires once.
- **Waitlist** (web): /api/waitlist Next proxy + lib/waitlist.ts
  (fetcher + isValidEmail) + _waitlist-form.tsx client island on
  the marketing landing under the existing CTAs. Idle/sending/
  done/error states inline; no full-page reload. 7 vitest cases.
- **/press page**: SSR with 50-word + 200-word blurbs, founder
  line, contact, placeholder logo links (Phase 5.9-wiring renders
  binaries). Reuses buildLegalMetadata.
- **docs/outreach/**: 5 templates calibrated per outlet — Durango
  Telegraph (dining beat), Durango Herald (business + tech), La
  Plata Mountaineer (community-events), KSUT (NPR human-interest,
  slower follow-up cycle), launch-day.md (Twitter/Bluesky/IG/
  LinkedIn posts + day-of timing). README cross-references the
  press page + send order.
Total: rspec 377/0/1 (+12); web vitest 99/99 (+7); pnpm typecheck
+ lint full-turbo green. Roadmap: ticked 5.1.1 (#182) + 5.1.1
plan (#181); reordered Next-up — this 5.10 PR at #1, then the
human-credential-gated wiring PRs (5.8/5.9/5.1.1) + the BLOCKED
cassette. **Phase 5 status after #183 merges**: every loop-
shippable launch piece is on master. Remaining work is entirely
human-gated (Anthropic cap retry, PostHog/Apple/Google accounts,
lawyer signoff, the actual `kamal deploy` from a laptop).
Anthropic cap clears in ~1.2h.

2026-04-30 22:21 — tick #87. PR #181 (Phase 5.1.1 plan) merged at
22:14 UTC; PR #180 (Phase 5.9 structural) also merged earlier.
Anthropic still capped (~1.6h to reset); cassette PR stays
BLOCKED. Picked the next unblocked Next-up item: **Phase 5.1.1 —
the actual Kamal+Hetzner+Neon migration** queued by last tick's
plan PR. Shipped the full rewrite of the API hosting story:
- Deleted `apps/api/fly.toml`. Added `apps/api/config/deploy.yml`
  (Kamal 2 config) — web + worker as separate roles, same image,
  GHCR registry, kamal-proxy with /up healthcheck + auto Let's
  Encrypt for api.bite-worthy.com, libjemalloc preload, all
  Phase 5.2/5.3 env wired through.
- `.kamal/hooks/pre-deploy` runs `bin/rails db:prepare` against
  the new image before kamal-proxy cuts traffic — Fly's
  release_command analog. Failed migration → no traffic cutover.
- `.kamal/secrets.example` documents every secret + where it
  comes from (Neon URL, GitHub PAT, Postmark token, R2 keys,
  OAuth secrets). Real `.kamal/secrets` gitignored.
- `.env.example` Fly section → Kamal/Hetzner/Neon section.
- README "Production deploy" rewrite — full hcloud + kamal flow
  inline, useful aliases table, where-things-live table updated
  for the new layout.
- ADR 0007 captures decision rationale: Hetzner CX22 (4GB/2vCPU
  in Ashburn at ~€5/mo) vs alternatives (Render, Railway, raw
  IaaS); Neon (managed Postgres) over Postgres-on-Hetzner-CX22
  (data survives box rebuilds; backups handled); Kamal vs
  Compose/Coolify/Dokku; GHCR vs Docker Hub. Trade-offs (you own
  the OS, single point of failure, mild lock-in) + mitigations.
- ADR 0002 marked Superseded by 0007 with one-paragraph note.
What stays unchanged: Dockerfile, bin/docker-entrypoint,
Biteworthy::ProductionSmoke + the rake task, all of Phase 5.2
(SMTP), 5.3 (R2 storage), 5.4 (Vercel for web), 5.5–5.10. The
migration is config-only on the deploy side; no app-code touched.
Tests: rspec 365/0/1 unchanged; pnpm typecheck + lint full-turbo
green. Roadmap: ticked the 5.1.1 plan PR (#181) in Done; this
implementation PR is what's "in flight" on Next-up #1. **Phase
5 launch playbook reset for the new stack**: the same human-
credential-gated pattern (Hetzner + Neon + GHCR PAT vs Fly +
Fly Postgres) but with cleaner cost ceiling. Cap clears in ~1.6h.

2026-04-30 21:47 — tick #86. PR #179 (Phase 5.8 analytics structural)
merged at 21:20 UTC, all CI green. Anthropic still capped (~2.2h
to reset); cassette PR stays BLOCKED. Picked the next unblocked
item: **Phase 5.9 — app store submission (structural)**. Same
ship-the-wiring-first split — loop ships everything that doesn't
need a paid Apple Developer or Google Play Console account.
Shipped:
- **Web privacy + terms** at `/privacy` and `/terms` (resolves
  the Phase 5.5 footer placeholder hrefs). Pure SSR templates
  filled with BiteWorthy's actual data flows: account, profile,
  reviews, restaurant_visits, suggestions; named services
  (Postgres+Fly.io / Cloudflare R2 / Anthropic / Postmark /
  PostHog). Both marked DRAFT with a banner — needs final
  lawyer pass before App Store submission. Allergen disclaimer
  is up top in /terms ("planning tool, not a medical device").
- `apps/web/src/lib/legal-meta.ts` extracted metadata helper +
  5 vitest cases (canonical title, OG url path joining,
  trailing-slash stripping, Twitter summary card, robots
  index/follow). Same testable shape as Phase 5.5's
  landing-meta.
- **Mobile store-listing**: `eas.json` with development /
  preview / production build profiles + a submit profile with
  placeholder values marking where Apple ID / ASC App ID / team
  ID / Play service-account path go.
  `apps/mobile/store-listing/` — App Store Connect metadata
  (name/subtitle/description/keywords/URLs/category/App Privacy
  answers/What's New template), Play Console metadata (short
  description/feature graphic/data safety/distribution), and a
  screenshots-plan.md naming the 5 marketing shots + the
  expo-router test-route flow Phase 5.9-wiring will use.
- `apps/mobile/assets/README.md` — required asset specs (icon,
  adaptive-icon, splash, favicon) + ui-tokens-derived design
  guidance + the sharp render pipeline 5.9-wiring follows.
Tests: 5 new vitest cases (web 92/92, +5). Typecheck + lint full-
turbo green; rspec 365/0/1 unchanged. Roadmap: ticked 5.8 (#179);
reordered Next-up so 5.9-structural is #1 and a new 5.9-wiring
entry is #4 (BLOCKED on dev accounts + lawyer review). **Phase
5 status**: every code-only PR has now shipped its structural
half. Remaining loop work: 5.10 (press kit + waitlist). The
human-credential-gated wiring queue: 5.1 deploy, 5.2 SMTP, 5.3
R2, 5.4 Vercel, 5.8-wiring (PostHog), 5.9-wiring (App Stores),
plus the long-blocked cassette PR. Anthropic cap clears at
00:00 UTC (~2.2h from now).

2026-04-30 21:19 — tick #85. PR #178 (Phase 5.7 Durango seed task)
merged at 20:47 UTC, all CI green including title-lint this time.
Anthropic still capped (~2.7h to reset); cassette PR stays
BLOCKED. Picked the next unblocked item: **Phase 5.8 — analytics
instrumentation (structural)**. Discovered Phase 4's
"placeholder track() events" were never actually wired — the
cross-cutting note in phase-4.md said they would be but no
call-sites have track() calls today. So 5.8 is a from-scratch
build of both abstraction + taxonomy. Shipped:
- New **`@biteworthy/analytics`** workspace package, zero deps,
  pure TS. Tracker interface + AnalyticsClient (the SDK contract
  apps will inject) + EVENTS map (9 stable funnel + engagement
  event names) + EventPropsMap (per-event payload type-safety
  → misspellings become tsc errors not split funnels) +
  noopTracker + createTracker factory. 6 vitest cases.
- **Web wrapper** at `apps/web/src/lib/track.ts` — env + DNT +
  `localStorage.bw_analytics_opt_out` aware. Returns noopTracker
  unless ALL of: `NEXT_PUBLIC_POSTHOG_KEY` set, DNT off, not
  opted out, AND a real AnalyticsClient injected. Phase 5.8
  ships always-noop because no client is injected yet — wiring
  follow-up adds posthog-js + the adapter. 5 vitest cases.
- **Mobile wrapper** at `apps/mobile/lib/track.ts` — same
  pattern but opt-IN by default (App Store privacy posture).
  4 jest cases.
- `docs/analytics.md` documents the 9 events + payload schemas +
  privacy posture + the structural-vs-wiring split. Mirrors the
  TS types so misspellings stay caught.
- ADR 0006 captures PostHog pick over Plausible / Mixpanel /
  Amplitude / Segment, why abstraction-first ship pattern,
  bootstrap path for the wiring follow-up.
Total: 15 new tests across 3 surfaces (web 87/87 +5; mobile
60/60 +4; analytics package 6/6). rspec 365/0/1 unchanged
(no API changes). pnpm typecheck (10 tasks) + lint (6 tasks)
all green; turbo cache miss only on the new package. Roadmap:
ticked 5.7 (#178); reordered Next-up so 5.8-structural is #1 and
a new 5.8-wiring entry is queued at #3 (depends on PostHog
credentials + posthog-js/RN install — operator task). **Phase 5
playbook continues**: every Phase-5 PR has split honestly into
loop-shippable wiring vs human-credential-gated hookup. Next
tick: 5.9 (mobile app store submission) — OR if Anthropic cap
clears at 00:00 UTC (~2.7h from now), retry the cassette PR.

2026-04-30 20:46 — tick #84. PR #177 (Phase 5.6 SEO city/diet pages)
merged at 20:19 UTC. Anthropic still capped (~3.2h to reset);
cassette PR stays BLOCKED. **Title-lint failed** on #177
("SEO" caps tripped `subjectPattern: ^(?![A-Z])(?!.*\.$).+$`) —
auto-merge config doesn't gate on title-lint so the merge happened
anyway; future titles avoid all-caps acronyms. Picked the next
unblocked Next-up item: **Phase 5.7 — seed 30 Durango
restaurants**. Operator-driven batch ingest tooling (the loop
ships the runner; populating the CSV + actually running the
seed is human work). Shipped:
- `docs/seeds/durango.csv.example` — column template
  (name/slug/address/phone/website/menu_source/neighborhood) with
  inline guidance + 3 example rows. The populated `durango.csv`
  stays out of git per inline note.
- `Biteworthy::DurangoSeed` runner. Idempotent — already-staged
  rows skip, per-row failures (UrlFetcher errors, missing files)
  caught + logged + tallied so one bad URL doesn't kill the
  batch. Uses Phase 2.8's UrlFetcher for HTTP sources, falls
  back to direct File.open for local paths. Restaurants stay
  :draft so Phase 2.5's 80%-accepted swipe-verify threshold
  still gates publication.
- `bin/rails biteworthy:seed:durango FILE=…` rake adapter with
  ENV overrides (CITY, CITY_NAME, CITY_REGION, WAIT, EXIT_CODE).
6 new specs covering happy path (2 rows → 2 runs created),
idempotent re-run (skips :staged), per-row failure isolation
(UrlFetcher::FetchError → :failed outcome, batch continues),
tally summary, draft-status guard, and CSV comment/blank-line
parsing. Total rspec 365/0/1 (+6); pnpm typecheck + lint
full-turbo green. Caught one bug during spec authoring:
Restaurant has no `has_many :ingestion_runs` association — fixed
by querying `IngestionRun.where(restaurant_id: …)` directly
rather than adding an association for a single check. Roadmap:
ticked 5.6 (#177); reordered Next-up. Eager-rebase applied.
**Avo dashboard tile** (subplan called for one) deferred — rake
stdout is sufficient for the seed run; an Avo widget is a
better stand-alone PR once the seed has run + we know what
counts matter. Next tick: 5.8 (PostHog instrumentation) — OR if
the Anthropic cap clears at 00:00 UTC (~3.2h from now), retry
the cassette PR (also unblocks the operator's actual Durango
seed run, since 30 menus need real Anthropic capacity).

2026-04-30 20:18 — tick #83. PR #176 (Phase 5.5 marketing landing)
merged at 19:46 UTC, all CI green. Anthropic still capped (~3.7h
to reset); cassette PR stays BLOCKED. Picked the next unblocked
Next-up item: **Phase 5.6 — SEO city/diet pages
(/durango/[diet])**. Indexable per-diet ranking pages (the
queries Durango folks actually type). Shipped both API + web:
- **API**: new `Cities::RestaurantRanking` service computes
  visible/total item counts per restaurant via one SQL query
  with Postgres `FILTER (WHERE …)` aggregation against the
  GIN-indexed `ingredient_ids uuid[]` + `tag_ids uuid[]` arrays.
  Order: `(visible_count DESC, name ASC)`. LEFT-OUTER joins so
  zero-item restaurants still appear; ignores draft restaurants;
  empty avoid lists handled with placeholder UUID so
  `ARRAY[]::uuid[]` doesn't trip Postgres. New
  `GET /api/v1/cities/:city_slug/restaurants?profile=:diet_slug`
  endpoint (public, unauthenticated). 404s on unknown city or
  diet slug. Flat route since the parent `:cities` resource has
  no controller (Phase 0 stub). 10 new specs (5 service + 5
  request); rspec 359/0/1 (+10).
- **Web**: `apps/web/src/app/durango/[diet]/page.tsx` pure-SSR.
  `generateStaticParams` pre-renders every curated diet at build
  time. `generateMetadata` composes deterministic title
  ("Vegan restaurants in Durango — BiteWorthy") + description.
  Unknown diet routes to Next's `notFound()`. Restaurants with
  zero safe items collapse into a `<details>` block at bottom so
  the page stays useful without burying the leads. Empty-state
  CTA back to /onboarding for the gap before Phase 5.7's seed
  run.
- `apps/web/src/lib/durango.ts` — fetcher +
  `DURANGO_DIET_SLUGS` curated constant (mirrors
  `db/seeds/dietary_profiles.yml`). Hard-coded rather than
  build-time-fetched: list changes once a quarter; mismatch is
  non-catastrophic (404 vs stale grid). 5 new vitest cases (URL
  composition, slug encoding, 404+500 propagation, slug list).
  Web vitest 82/82 (+5).
- `app/sitemap.ts` extended to enumerate diet URLs via the
  `dietSlugs` hook PR #175 already wired in.
Local: pnpm typecheck + lint full-turbo green; rspec 359/0/1
(+10). Roadmap: ticked 5.5 (#176); reordered Next-up. Eager-
rebase applied. Surfaced one **Discovered**-worthy gap during
implementation: addresses table has no `neighborhood` column;
the subplan asked for a per-row neighborhood label which I left
out. Worth a Phase 5+ followup once the launch market grows
beyond "Durango itself." Next tick: 5.7 (seed 30 Durango
restaurants) — OR if the Anthropic cap clears at 00:00 UTC
(~3.7h from now), retry the cassette PR.

2026-04-30 19:45 — tick #82. PR #175 (Phase 5.4 web deploy wiring)
merged at 19:18 UTC, all CI green. Anthropic still capped (~4.3h
to reset); cassette PR stays BLOCKED. Picked the next unblocked
Next-up item: **Phase 5.5 — marketing landing page at /**.
Replaced the "Pre-MVP" placeholder home page with the real launch
landing. Pure SSR, Tailwind-only, ui-tokens colors. Shipped:
- **Hero** with one-line value prop ("Scan any menu, see only
  what you can eat."), subhead, primary CTA → /onboarding (entry
  to the Phase 3.2/3.8 6-tap profile flow). iOS + Android render
  as "Coming soon" badges until Phase 5.9 lands real store URLs
  — honest scope vs fake hrefs that 404 on launch announcement.
- **Three-up feature row** (Scan / Pick filter / See safe dishes)
  on a soft `bg-bite-light/30` background.
- **Durango note** explicit launch-market positioning ("30
  independent restaurants, not chains").
- **Footer** with copyright, /privacy /terms /press placeholders
  (Phase 5.9 + 5.10 ship the actual pages — links are markup-
  stable across PRs), real GitHub link.
- **Open Graph + Twitter card metadata** via Next 13+ `metadata`
  export. Pulled into pure-TS `apps/web/src/lib/landing-meta.ts`
  so the strings are unit-testable. `metadataBase` derived from
  `NEXT_PUBLIC_SITE_URL`; preview deploys still emit a canonical
  `/` so SEO doesn't split across vercel.app subdomains.
5 new vitest cases for `buildLandingMetadata` (title/description,
trailing-slash stripping in OG URL + image, Twitter
summary_large_image, canonical, OG siteName). Web vitest 77/77
(+5). One tsc gotcha caught during spec authoring: Next 16's
`Twitter` type is a discriminated union — `meta.twitter?.card`
only resolves with narrowing. Fixed via a local cast in the
spec; production code stays type-correct. Local: pnpm typecheck
+ lint full-turbo green; rspec 349/0/1 unchanged. Roadmap:
ticked 5.4 (#175); reordered Next-up. Eager-rebase applied.
**Phase 5 production infrastructure stays structurally complete**;
this PR opens the public-surface bucket. Next tick: 5.6
(/durango/[diet] SEO pages — sitemap hook from #175 already
ready) — OR if the Anthropic cap clears at 00:00 UTC (~4h
from now), finally retry the cassette PR.

2026-04-30 19:17 — tick #81. PR #174 (Phase 5.3 R2 blob storage)
merged at 18:48 UTC, all CI green. Anthropic still capped (~4.7h
to reset); cassette PR stays BLOCKED. Picked the next unblocked
Next-up item: **Phase 5.4 — production web deploy (Vercel +
bite-worthy.com)**. Loop-shippable wiring split out from
human-only provisioning per the subplan's Stop conditions.
Shipped:
- `apps/web/vercel.json` — minimal config: framework=nextjs,
  region=iad1 (closest free-tier to Durango; iad→den ~30ms RTT
  to the Phase 5.1 API), security response headers
  (X-Frame-Options, X-Content-Type-Options, Referrer-Policy).
- `apps/web/public/robots.txt` — allow all bots; disallow
  `/api/*` proxy routes (server-side adapters, not user pages);
  points crawlers at /sitemap.xml.
- `apps/web/src/app/sitemap.ts` (Next 13+ App Router entry) +
  `apps/web/src/lib/sitemap.ts` (pure-TS generator). Today
  covers /, /login, /signup with sensible priorities/changefreqs;
  has hooks (`dietSlugs`, `restaurantSlugs`) for Phase 5.6 +
  Phase 5.7 to extend without touching Next. Encodes slugs with
  reserved chars; strips trailing slashes from baseUrl.
- `apps/web/src/lib/cookie-options.ts` — extracted auth-cookie
  attribute builder reading `NEXT_PUBLIC_COOKIE_DOMAIN`. Prod
  scopes cookie to `.bite-worthy.com` (works across www + future
  app subdomain); dev/CI leave it unset (localhost cookies MUST
  NOT carry a domain attribute or browsers silently drop them).
  3-line refactor of `api/auth/[action]/route.ts` to use it.
- `apps/web/.env.example` — first one for the web app. Documents
  `NEXT_PUBLIC_API_BASE` + `NEXT_PUBLIC_COOKIE_DOMAIN`.
- ADR 0005 captures Vercel pick (free tier handles Durango-scale,
  native Next.js 15 support, preview deploys per PR) vs CF Pages
  (cheaper at scale but less mature Next runtime). Cookie-domain
  rationale captured. Deploy lifecycle: push to master →
  Vercel auto-deploy; push to feature branch → preview URL.
- Web README gets new "Production deploy" section.
Tests: 10 new vitest cases (5 sitemap + 5 cookie-options). Web
vitest 72/72 (+10). Local: pnpm typecheck + lint full-turbo
cached green; rspec 349/0/1 pending unchanged. Roadmap: ticked
5.3 (#174); reordered Next-up. **Eager-rebase applied** before
branching. After PR #175 merges, **Phase 5's production
infrastructure is structurally complete** (5.1 API deploy, 5.2
SMTP, 5.3 R2 storage, 5.4 web deploy all loop-shipped); next
steps shift to public surface (5.5 marketing landing, 5.6
SEO city pages) and seed motion (5.7 Durango ingest). Anthropic
cap clears at 00:00 UTC (~4.7h from now); cassette retry
unblocks then.

2026-04-30 18:47 — tick #80. PR #173 (Phase 5.2 SMTP wiring) merged
at 18:20 UTC, all CI green. Anthropic still capped (~5.2h to
reset); cassette PR stays BLOCKED. Picked the next unblocked
Next-up item: **Phase 5.3 — production blob storage**. Closes
the long-deferred Phase 2 + 4 + 4.11 blob gap. Shipped:
- `config/storage.yml` adds `:r2` block. R2 speaks S3 API so
  `aws-sdk-s3` works unchanged — only endpoint + region (must
  be "auto") + `force_path_style: true` differ. `:amazon` stays
  as a one-line-flip fallback for R2 outages.
- `production.rb` flips `active_storage.service` from `:amazon`
  to `:r2`.
- New `Biteworthy::StorageBackfill` runner +
  `bin/rails biteworthy:storage:backfill` rake task. Migrates
  any blob whose `service_name` differs from the configured
  service. Idempotent — already-on-target blobs are no-ops.
  Per-blob `[ok]/[skip]/[FAIL]` log; `EXIT_CODE=1` makes CI
  fail loud on any failure. Reusable for future service flips.
- ADR 0004 captures R2-over-S3 decision (zero egress charges
  become real money at scale: $0/GB vs $0.09/GB; ~$45/mo
  saved at modest growth scale). Why-not for Backblaze/Wasabi
  (operational maturity) + why-not for R2-native gem
  (portability). Direct CDN serving via public R2 URLs deferred
  to Phase 5+ — ActiveStorage's signed-redirect adds ~40ms per
  image, invisible at Durango-beta volume.
- `.env.example` adds R2_* placeholders + commented AWS_*
  fallback block. README gets new "Blob storage" section with
  the bootstrap + backfill command.
4 new specs in `spec/lib/storage_backfill_spec.rb` (already-
on-target skip, cross-service migration, per-blob failure
capture without aborting, summary counts). Caught one bug
during spec authoring: `service_name_was` returns nil after
update_columns (which bypasses dirty tracking) — fixed by
capturing `from_service` before calling migrate. Local: rspec
349/0/1 pending (+4); pnpm typecheck + lint full-turbo cached.
Roadmap: ticked 5.2 (#173); reordered Next-up. **Eager-rebase
applied** before branching. Next tick: babysit PR #174 to
merge, then 5.4 (Vercel web deploy) — OR if Anthropic cap
clears at 00:00 UTC (~5h from now), finally retry the
cassette.

2026-04-30 18:18 — tick #79. PR #172 (Phase 5.1 deploy wiring)
merged at 17:45 UTC after the rebase, all CI green. Anthropic
still capped (~5.7h to reset); cassette PR stays BLOCKED. Picked
the next unblocked Next-up item: **Phase 5.2 — SMTP wiring**.
Closes the long-deferred Phase 4 email gap. Shipped:
- `config/environments/production.rb` switches `delivery_method`
  to `:smtp` with `smtp_settings` reading `SMTP_*` env vars
  (defaults to Postmark's `smtp.postmarkapp.com:587` + STARTTLS +
  plain auth). `raise_delivery_errors = true` so misconfig fails
  loud; Solid Queue retries transient errors. `default_url_options`
  derived from `MAILER_HOST` (web origin, not API origin) so
  claim-verify links + Devise password resets render correct URLs.
- New `BiteworthyMailer.smoke_test(to:)` + text/html templates +
  `Biteworthy::EmailSmoke` runner + `bin/rails biteworthy:email:smoke
  EMAIL=...` rake task. Self-contained, no DB record needed —
  runnable on a fresh deploy. Reports SMTP Message-ID per delivery;
  `EXIT_CODE=1` makes CI fail loud.
- ADR 0003 captures Postmark-via-SMTP decision (why Postmark over
  SES/SendGrid/Mailgun/Resend; why SMTP over postmark-rails gem;
  secret-rotation lifecycle; what works after secrets are set).
- `.env.example` adds SMTP_* placeholders + MAILER_HOST. README
  gets a new "Email" section with bootstrap + smoke command.
After this merges, Devise password reset + Phase 4.9's
RestaurantClaimMailer.verify_email both light up automatically —
no per-mailer code change needed (the wiring is per-environment).
Tests: 4 new specs in `spec/lib/email_smoke_spec.rb` (happy path,
log format, mailer-raise capture, text+html template rendering).
Local: rspec 345/0/1 pending (+4); pnpm typecheck + lint
full-turbo cached green. Roadmap: ticked 5.1 (#172) and the Phase
5 subplan (#171); reordered Next-up. **Eager-rebase mitigation
applied** (lesson from #172 going DIRTY): ran
`git fetch origin && git pull origin master --ff-only` before
branching this tick so 5.2 starts on the freshest master.
**Note**: tick #78 was the rebase fix for PR #172 (resolved a
docs/status.md conflict between #170-base and #171-merged); its
own status entry got lost in #172's squash-merge, hence the
#77 → #79 jump.

2026-04-30 17:19 — tick #77. PR #171 (Phase 5 subplan) merged at
16:48 UTC. Anthropic still capped (~6.5h to reset); cassette PR
stays BLOCKED. Picked the next unblocked Next-up item: **Phase
5.1 — production API deploy wiring**. Split the work cleanly into
"loop-shippable wiring" vs "human-only provisioning" per the
subplan's Stop conditions. Shipped:
- Multi-stage `apps/api/Dockerfile` (Rails 8 prod, libpq + libvips
  + imagemagick + libjemalloc2, non-root rails:1000 user) +
  `.dockerignore` (no secrets/.git/specs in upload) +
  `bin/docker-entrypoint` (runs db:prepare on the puma process
  only — release_command is the belt-and-suspenders).
- `apps/api/fly.toml` with two processes (`app` puma,
  `worker` `bundle exec rake solid_queue:start`), region DEN
  (closest to Durango), `/up` healthcheck every 30s, force_https,
  separate `[[vm]]` per process. Workers explicitly OUT of puma
  (`SOLID_QUEUE_IN_PUMA=false`) — auto_stop would kill in-flight
  ingestion jobs. libjemalloc2 LD_PRELOAD'd to trim puma RSS.
- `lib/tasks/production.rake` thin Rake adapter +
  `app/services/biteworthy/production_smoke.rb` (extracted so
  the spec doesn't need Rake's DSL). Read-only smoke: GET /up +
  GET /api/v1/restaurants/:slug/items, one timing line per check,
  exits non-zero with `EXIT_CODE=1` so CI can fail a deploy.
  Stays read-only so it's safe on every deploy; Phase 5.7's seed
  task is the right place for IngestionRun creation against prod.
- `docs/adr/0002-production-hosting.md` capturing implementation-
  level Fly.io decisions (machine model, region, process split,
  Postgres dev tier to start, secret rotation lifecycle, why not
  Render/Railway/Heroku/IaaS). Refines ADR 0001 rather than
  superseding it.
- `apps/api/.env.example` adds `PUBLIC_HOST`,
  `SOLID_QUEUE_IN_PUMA=false`, commented Rails 8 prod ENV.
- `apps/api/README.md` new "Production deploy" section with the
  one-time bootstrap + every-deploy commands.
What still needs a human (per ADR 0002 step list): fly auth login,
fly launch, fly postgres create/attach, fly secrets set
(RAILS_MASTER_KEY + ANTHROPIC_API_KEY + DEVISE_JWT_SECRET_KEY +
ADMIN credentials), fly deploy, DNS for api.bite-worthy.com (CNAME
→ biteworthy-api.fly.dev) + fly certs add, then run the smoke
task to confirm. Roadmap: ticked 4.11.2 (#170) and 4.11.4 (#169) +
flagged Phase 4.11 structurally complete in PR #171; next-up after
this PR is 5.2 (SMTP). Tests: 4 new specs against
`Biteworthy::ProductionSmoke` (no-restaurants branch, happy path
with one published restaurant, non-2xx /up, network-error
capture). Local: rspec 341/0/1 pending (+4); pnpm typecheck +
lint full-turbo cached green.

2026-04-30 16:46 — tick #76. PR #170 (Phase 4.11.2 structural)
merged at 16:18 UTC. Anthropic still capped (~7h to reset);
Next-up was a single `[BLOCKED]` cassette item. Per the
roadmap's stated cadence ("After Phase 4.11 ships, the loop
will draft `docs/plans/phase-5.md` (Durango launch) the same way
Phase 4 was drafted at the end of Phase 3"), and given Phase 4.11
is **structurally complete** (every line of consumer + producer
code on master after #170; cassette is the only outstanding
work), this tick mirrors PR #155 — a plan-only PR drafting
Phase 5. Decomposed Phase 5 into 10 tasks across three buckets:
production deploys (5.1 Fly.io API, 5.2 SMTP Postmark, 5.3 R2
ActiveStorage, 5.4 Vercel web on bite-worthy.com), public
surface (5.5 marketing landing replacing /, 5.6 SEO
/durango/[diet] pages), and seed + launch motion (5.7
30-restaurant batch ingest from CSV, 5.8 PostHog funnel wiring
real, 5.9 TestFlight + Play Internal app submission, 5.10 press
kit + Durango outreach + waitlist). Stop conditions enumerated:
Anthropic billing tier, SMTP creds, R2 bucket + IAM, App Store
+ Play Store team accounts, real Durango menu CSV (research
task), DNS for bite-worthy.com, lawyer-skim of privacy/terms.
Cross-cutting: OpenAPI codegen on every endpoint PR; existing
Discovered followups (jest-expo + web RTL wiring; auto-merge
race) carry over. Roadmap: ticked 4.11.2 (#170) + flagged Phase
4.11 structurally complete; replaced Next-up with the Phase 5
batch plus the holdover BLOCKED cassette PR. Local: pnpm
typecheck + lint full-turbo cached green; no code changes.
**Plan PR awaiting human review** — subsequent ticks will pick
from the new queue (5.1 first once a human approves the plan;
cassette retry once the cap clears at 2026-05-01 00:00 UTC).

2026-04-30 16:17 — tick #75. PR #169 (Phase 4.11.4 photo render)
merged at 15:48 UTC with all CI green including title-lint (the
lowercase-after-colon convention now baked in). Anthropic still
capped until 2026-05-01 00:00 UTC (~7.5h away). Next-up was
all-`[BLOCKED]` so I re-read the 4.11.2 subplan: its **Stop**
clause explicitly says "if capped, push the schema + prompt + spec
stub and skip the live re-record." Pivoted to **Phase 4.11.2
structural** — everything except the live cassette recording.
- `MenuExtractionSchema` gains optional per-item `image_bbox`
  shaped as `oneOf: [null, {x, y, w, h}]`. Restructured from
  `type: [object, null]` to `oneOf` because json-schema gem
  defaults to draft-04 where union types dilute sub-object rules
  (caught by the spec — first 2 cases failed until I switched).
  Also `exclusiveMinimum: true` (boolean form) for w/h since
  draft-04 doesn't support the numeric form. Items omit the field
  entirely when no inline photo; null also accepted defensively.
- `ExtractMenuPrompt::SYSTEM_INSTRUCTIONS` gets a "Per-dish
  photos" paragraph: 0,0=top-left, 1,1=bottom-right, omit when no
  inline photo, prefer the photo physically closest to the item
  name when a page has multiple.
- `ResolveTagsJob#materialize_ingestion_items!` copies
  `item["image_bbox"]` (or nil) onto IngestionItem so 4.11.3's
  promote! crops + attaches without further plumbing.
- New spec `spec/services/ingestion/menu_extraction_schema_spec.rb`
  (7 cases) + extended resolve_tags_job_spec covering bbox flow.
Roadmap: ticked 4.11.4 (#169); reorganized Next-up so 4.11.2
structural (this PR) is #1 and the combined 4.11.0 / 4.11.2
cassette work is #2 (BLOCKED, single recording covers both since
VCR body-matching auto-supersedes the older cassette). Local:
rspec 337/0/1 pending (+8); pnpm typecheck + lint cached green.
**Phase 4.11 status after this PR**: every line of consumer-side
code is on master + the extractor is asking the model for bboxes;
the only outstanding work is the live recording when the cap
clears.

2026-04-30 15:47 — tick #74. PR #168 (Phase 4.11.3 promote+serialize)
merged at 15:24 UTC. **Anthropic still capped** until 2026-05-01
00:00 UTC (~8.5h away) — 4.11.0 (cassette) + 4.11.2 (extract
bboxes) stay blocked. Pivoted to **Phase 4.11.4** (render dish
photos on web + mobile), pure consumer of the
`photo_url: string | null` field 4.11.3 shipped. Web
RestaurantClient ItemRow renders a plain `<img>` with
`loading="lazy"` + `h-48 w-full object-cover` (Rails signed-blob
URLs vary per env so next/image's loader config doesn't fit).
Mobile [id].tsx ItemRow renders an `expo-image` `<Image>` with
`contentFit="cover"`, fixed 180px height, bgAlt placeholder
(expo-image was already a dep + handles caching better than
react-native's stock). Both render conditionally — null
`photo_url` produces no DOM/RN element. Acceptance asked for one
vitest + one jest snapshot of the render itself; deferred to the
existing Discovered jest-expo wiring followup, which I expanded
to cover web `@testing-library/react` + jsdom too (neither app
has component-render test infra today). What I shipped instead:
a pure-TS vitest in `apps/web/src/lib/__tests__/restaurants.test.ts`
asserting a fetched RestaurantItemsResponse with mixed photo_url
values (string + null) round-trips through the fetcher. Roadmap
ticks: 4.11.1 (#167) and 4.11.3 (#168). Next-up trimmed: queue is
now [4.11.4 (this PR), 4.11.0 BLOCKED, 4.11.2 BLOCKED]. Local:
typecheck + lint cached green; web vitest 62/62 (+1 new); mobile
jest 56/56; rspec 36/0 on touched files (no API changes).
**Title-lint catch**: PR #168 title "IngestionItem promote attaches…"
failed `amannn/action-semantic-pull-request`'s
`subjectPattern: ^(?![A-Z])(?!.*\.$).+$` (must start lowercase
after the colon). Non-blocking — didn't gate auto-merge — but
future PR titles should respect it.

2026-04-30 15:21 — tick #73. PR #167 (Phase 4.11.1 cropper) merged at
14:51 UTC. **Anthropic still capped** until 2026-05-01 00:00 UTC
(~9h away) — skipped retry of the 4.11.0 cassette + 4.11.2 prompt
work, pivoted to 4.11.3 (consumer-side promote/serialize) which has
zero Anthropic dependency. Item gains `has_one_attached :photo`
(reuses Phase 4.3's MAX_PHOTO_BYTES + ALLOWED_PHOTO_TYPES). Extended
`IngestionItem#promote!` with a `attach_dish_photo!(created)` rescue
block: when `image_bbox` is present, fetches the run's first source
blob and crops via `Ingestion::DishPhotoCropper`, attaches the JPEG
to the new Item.photo. Cropper failures (bad bbox, unreadable blob,
no source) log + skip — promotion always succeeds so a single weird
coordinate doesn't block the verify queue. Items endpoint serializer
emits `photo_url` (signed `rails_blob_url` with PUBLIC_HOST/
request.base_url fallback, mirrors Phase 4.3's review pattern);
preloaded `photo_attachment: :blob` on both index + show to skip
N+1. RestaurantItem TS types in web + mobile gain
`photo_url: string | null`. Mobile factory updated with
`photo_url: null` default. Tests: 5 new specs (4 promote behavior +
1 serializer payload) — rspec 329/0/1 pending; pnpm typecheck +
lint cached green; mobile + web vitest/jest green. Pre-4.11.2
ingestions stay null on the bbox column so this is a no-op for
them; once 4.11.2 lands, photos flow through with no further
consumer changes. **Date fix**: prior tick #72 mis-stamped itself
2026-05-01; actual UTC clock today is 2026-04-30 (PR #167 merge
timestamp confirms).

2026-05-01 14:30 — tick #72. PR #166 (Phase 4.11 plan + master fix) merged at 14:18 UTC.
**Cassette PR (4.11.0) blocked again**: tried recording with the same
sample.jpg, hit HTTP 400 "regain access on 2026-05-01 at 00:00 UTC"
— I miscounted last tick (00:00 UTC is the START of May 1, ~10
hours away from the cron's 14:18 UTC reading, not behind us).
Rolled back the spec edit + deleted the empty cassette dir; per
playbook §7, pivoted to Phase 4.11.1 since it has zero Anthropic
dependency. New migration adds image_bbox jsonb to ingestion_items
(nullable, validation lives at app layer). New
Ingestion::DishPhotoCropper service: takes a blob + normalized
{x,y,w,h} bbox + optional padding (default 5%), reads via
MiniMagick, clamps the padded box to source dimensions so a
near-edge bbox doesn't slice off, returns a Cropped struct
({io, width, height, content_type}) ready to attach via
ActiveStorage. Accepts symbol OR string keys (jsonb roundtrip
brings strings; in-Ruby callers prefer symbols). Hard-validates
input: missing key, non-numeric, x/y out of [0,1], w/h ≤ 0,
non-Hash all raise InvalidBboxError so the calling promote! can
rescue cleanly. Tests: 10 specs against the committed JPEG fixture
(spec/fixtures/menus/sample.jpg from the prepped 4.11.0 work) —
JPEG roundtrip via MiniMagick decode, padding behavior, edge
clamping, every validation branch, ActiveStorage::Blob duck-typing.
Kept the JPEG fixture committed (it's needed for 4.11.1 specs and
will be needed again for 4.11.2's cassette). Added explicit
`apt-get install imagemagick` step to ci-api.yml so the runner
keeps the binary even if the ubuntu-latest image changes (locally
also brew-installed imagemagick to run the specs). Local: rspec
324/0/1 pending; pnpm typecheck/lint cached green (no JS changes).

2026-05-01 14:00 — tick #71. PR #165 (Phase 4.10) merged at 13:51 UTC.
**Phase 4 feature-complete** (4.1 → 4.10 all shipped: session cookies
→ persistent overrides → review API → mobile review UX → web review
UX → moderation queue → user profile pages → history → restaurant
claim → suggestion queue UX). Per the roadmap's stated cadence,
this tick is a plan-update PR: no code, just
`docs/plans/phase-4.11-dish-photos.md` and the Next-up queue
update. Decomposed Phase 4.11 (per-dish photo extraction) into 5
PR-sized tasks plus the long-deferred Phase 2.3 cassette work as
prerequisite 4.11.0: 4.11.1 schema (image_bbox jsonb on
ingestion_items, normalized 0..1 fractions) + DishPhotoCropper
service (image_processing + 5% pad); 4.11.2 extend
MenuExtractionSchema + ExtractMenuPrompt to ask Anthropic vision
for bboxes per item, re-record cassette; 4.11.3 Item gains
has_one_attached :photo + IngestionItem#promote! crops + attaches
on accept; 4.11.4 web + mobile RestaurantItem renders photo_url
inline. Stop conditions called out: ANTHROPIC_API_KEY daily cap
(blocked previous tick — should be reset by now); bbox accuracy
unproven (acceptance bar: visual sanity-check on 3 menus, NOT
pixel-perfect); cost increase ~10–20% per page in output tokens.
Cross-cutting notes: Phase 2.9 cost dashboard validates the bump;
OpenAPI codegen gains Item.photo_url; no mobile camera changes.
Marked Phase 4 ✅ in roadmap header with the achieved-2026-04-30
demo line; added a Phase 4.11 interstitial section. Plan PR
awaits human review before items auto-run, same protocol as the
Phase 3 (#145) and Phase 4 (#155) plan PRs.

2026-05-01 13:30 — tick #70. PR #164 (Phase 4.9) merged at 13:24 UTC.
Picked up Phase 4.10 — suggestion queue UX (the last item in Phase 4).
New `SuggestionResolver` service with five item-edit kinds
(add_ingredient, remove_ingredient, add_tag, remove_tag, rename),
each accept materializing a real Item / ItemIngredient / ItemTag
change with `confidence: confirmed, source: human` (mirrors
IngestionItem#promote!). Wrapped in one transaction so a payload
validation failure rolls back both the side effect and the
Suggestion status. Three endpoints: POST anonymous-allowed (so a
diner without an account can still flag a fix), GET owner-only
(restaurant.claimed_by_user_id or admin), PATCH owner-only with
'accepted' | 'rejected' decision. All gated through one
`gate_owner!` helper. Web: three Next proxy routes mirroring the
auth shape (suggestion-create forwards a JWT IF the cookie has
one; the other two require it). New `lib/suggestions.ts` client
with SuggestionError preserving status + kind so the UI can
distinguish 401 (bounce to /login), 403 (you don't own this
restaurant), 422 + InvalidPayloadError (couldn't accept that —
double-check the value). `<SuggestFixClient>` form on the item
detail page (kind dropdown + value input + dynamic placeholder
hint per kind). `/restaurants/[slug]/suggestions` owner queue page
shows pending suggestions with Accept / Reject buttons; rows drop
locally on decision rather than re-fetching. Tests: 11 resolver
specs (every kind end-to-end + idempotence + rollback +
unsupported kind), 12 controller specs (anonymous create,
authenticated create attribution, unsupported kind 422, owner
gate on index/update, admin override, accept materializes,
InvalidPayload rollback), 7 vitest for the web client. Local:
rspec 314/0/1 pending; web vitest 61/61; mobile jest 56/56;
pnpm typecheck/lint cached green. **After this PR ships, Phase 4
is feature-complete** (4.1 → 4.10 all merged); next tick drafts
the Phase 4.11 dish-photo subplan per the user's earlier ask.

2026-05-01 13:00 — tick #69. PR #163 (Phase 4.8) merged at 12:52 UTC.
Picked up Phase 4.9 — restaurant claim flow with domain-email
verification. New `RestaurantClaim` service that reuses the
`suggestions` polymorphic queue with `kind: 'claim'` (no schema
change): `request_claim` creates a Suggestion holding token + email
+ expiry in payload jsonb; `verify` looks up the token, validates
expiry, marks the restaurant `claimed_at` + `claimed_by_user_id`,
and accepts the Suggestion in one transaction. Domain match
heuristic: email's host vs restaurant.website host (with leading
`www.` stripped, case-insensitive) — mismatches still create the
Suggestion but mark `auto_acceptable: false` for admin review via
Avo's existing Suggestion resource. Endpoints: `POST
/api/v1/restaurants/:id/claim` (auth-only) enqueues
RestaurantClaimMailer.verify_email; `GET .../claim/verify?t=<token>`
is anonymous (token IS the credential). Mailer ships HTML+text
templates; dev environment also logs the verify URL to satisfy the
Phase 4 SMTP stop condition. Restaurants endpoint extended with
`claimed_at` + `claimed_by_user_id` (non-PII) so the web page can
hide the claim button when already claimed without a roundtrip.
Web: `/api/restaurants/[slug]/claim` proxy + verify proxy (the
verify proxy is anonymous — the token alone is the credential),
new `lib/restaurant-claim.ts` client, `<ClaimSection>` inline form
on RestaurantClient (hidden when restaurant is claimed; bounces
401 to /login), and standalone verify landing page at
`/restaurants/[slug]/claim/page.tsx` that handles the four error
kinds (Invalid/Expired/AlreadyClaimed + missing-params) with
human-readable messages. Tests: 14 service specs (domain match
matrix, request creation, expiry, idempotence, AlreadyClaimed
race), 11 controller specs (POST auth gate, mailer enqueue, slug
lookup, conflict, anonymous verify happy + invalid + expired),
6 vitest for the web client (POST URL + credentials + ClaimError
kind preservation, verify URL encoding, ExpiredTokenError surface).
Local: rspec 291/0/1 pending; web vitest 54/54; mobile jest 56/56;
pnpm typecheck/lint cached green.

2026-05-01 12:30 — tick #68. PR #162 (Phase 4.7) merged at 12:23 UTC.
Picked up Phase 4.8 — "My filtered menus" history. New
`restaurant_visits` table (user_id, restaurant_id, viewed_on,
items_visible_count, items_hidden_count) with composite unique
index on (user_id, restaurant_id, viewed_on) so the upsert is
race-safe — a user reloading the same restaurant five times in
a day produces a single row with the latest counts. Counts are
denormalized so the History list renders without touching items
or reviews. New `RecordRestaurantVisitJob` that
`find_or_initialize_by` + saves; rescues InvalidForeignKey
silently (best-effort) and retries RecordNotUnique once.
ItemsController#index now enqueues the job when current_user is
present, swallowing any enqueue exception so the response always
200s. New `GET /api/v1/profile/history` returns paginated visits
newest-first with restaurant + city info; auth-only. Web: Next
proxy at `/api/profile/history` + client-side `/history` page
that bounces 401 → /login. Mobile: `/history.tsx` mirror that
reads JWT from keychain and bounces to /login if absent or 401.
Tests: 5 job specs (create, idempotent upsert, separate days,
swallowed FK error, default viewed_on); 4 controller specs (auth
gate, newest-first ordering with city, limit/offset, no cross-user
leak); 3 items-endpoint specs (enqueue with auth, no enqueue
anonymous, swallow enqueue failure); 3 vitest + 3 jest for the
JS clients. Local: rspec 266/0/1 pending; web vitest 48/48;
mobile jest 56/56; pnpm typecheck/lint cached green.

2026-05-01 12:00 — tick #67. PR #161 (Phase 4.6) merged at 11:49 UTC.
**Cassette PR blocked**: started the cassette work (planned for this
tick at user request), converted IMG_6973.HEIC → JPEG, dropped at
spec/fixtures/menus/sample.jpg, replaced the skip block with a real
VCR.use_cassette around ExtractMenuJob.perform_now. Recording
attempt failed with HTTP 400: "You have reached your specified API
usage limits. You will regain access on 2026-05-01 at 00:00 UTC."
Per playbook §7 (secrets the loop doesn't have / blocked), rolled
back the local edits + reported to user; can retry after the cap
resets. Pivoted to Phase 4.7 — user profile pages — since it has
no Anthropic dependency. New `GET /api/v1/users/:handle` returns
the public payload (handle, display_name, member_since,
reviews_count, restaurants_reviewed_count, recent_reviews[10]
with item + restaurant context). Sensitive fields explicitly
excluded; one rspec asserts the response keys are exactly the
allowed set AND that user.email + user.jti don't appear anywhere
in the response body. Hidden reviews drop out via the same
.visible scope from 4.6. Web: server-rendered `/u/[handle]/page.tsx`
with stat cards + recent-reviews list linking to
/restaurants/<slug>/items/<id>. Mobile: `/users/[handle].tsx`
mirror with the same structure; review rows push to /items/[id]
via the typed router.push. Tests: 5 rspec (public payload, no
PII leak, hidden-review exclusion, 10-cap newest-first, 404 on
unknown handle); 4 vitest for the web client; 3 jest for the
mobile client. Roadmap: cleaned up duplicated Next-up entries
(stale items from earlier ticks), added a note that Phase 4.11
dish-photo subplan drafts after Phase 4.10. Local: rspec 254/0/1
pending; web vitest 45/45; mobile jest 53/53; pnpm typecheck/lint
cached green.

2026-05-01 11:30 — tick #66. PR #160 (Phase 4.5) merged at 11:18 UTC.
Picked up Phase 4.6 — review moderation queue. New migration adds
`hidden_at` + `hidden_reason` + `flagged_at` columns to reviews
with partial indexes scoped to the two hot paths (public feed
lookup `WHERE hidden_at IS NULL`, queue lookup
`WHERE flagged_at IS NOT NULL AND hidden_at IS NULL`). Review model
gained `.visible` / `.hidden` / `.awaiting_moderation` scopes,
`HIDDEN_REASONS` constant (spam | abuse | duplicate | off_topic),
`hide!(reason:)` + `unhide!` helpers, and a `before_save` callback
that runs `suspicious?` and drops a `flagged_at` timestamp when the
body trips the heuristic (URL detection + 9-word profanity list,
word-boundary matched so "ducks" doesn't false-positive). Public
API: items endpoint's `reviews_count` and reviews#index both went
from `Review.where(...)` to `Review.visible.where(...)` so hidden
reviews drop out of the public feed instantly. Avo: new
`Avo::Resources::Review` (read-write for admins) with two filters
(Awaiting moderation boolean + Visibility select), three actions
(Hide with reason picker, MarkSpam shortcut, Unhide). Each action
extracts pure logic to `self.method` so specs can call without the
controller lifecycle (Phase 2.5 pattern). Tests: 16 model specs
covering scopes, the heuristic, auto-flagging, hide/unhide
idempotence + reason validation; 4 Avo action specs (hide_all
counts + skip-already-hidden + flag-clearing on hide; unhide_all
counts); 1 reviews#index spec for the visible scope; 1 items
endpoint spec for the visible reviews_count. Local: rspec 249/0/1
pending; pnpm typecheck/lint cached green (no JS changes).

2026-05-01 11:00 — tick #65. PR #159 (Phase 4.4) merged at 10:48 UTC.
Picked up Phase 4.5 — web review UX. Mirror of mobile 4.4 on Next.js.
Two new Next API proxy routes: `/api/items/[id]/reviews` (GET +
POST, multipart-aware) and `/api/reviews/[id]` (PATCH + DELETE).
Both proxy through `getServerJwt` from the bw_session cookie. New
`apps/web/src/lib/reviews.ts` API client (fetchReviews via proxy,
fetchReviewsServer for SSR direct, createReview that switches
JSON/multipart based on photo presence, updateReview, deleteReview);
401 surfaces as ReviewError with status preserved so the caller can
bounce to /login. New `fetchItem(slug, id)` server-side fetcher in
restaurants.ts. SSR page at
`apps/web/src/app/restaurants/[slug]/items/[id]/page.tsx` runs
`Promise.all` over restaurant + item + initial reviews; notFound()
on either restaurant or item miss; reviews fall back to empty array
on fetch error. Client island ReviewsClient handles compose form
(5-star tap, optional body textarea, optional File photo) + Load
more pagination starting at offset=20. The existing RestaurantClient
got per-item review badges that link to `/restaurants/<slug>/items/<id>`
matching the mobile flow. Tests: 11 new vitest cases covering
proxy URL construction, query-param presence/absence, JSON vs
multipart switching, 401/403/404 → ReviewError, no client-side
Authorization header (proxy injects from cookie). Local: rspec
229/0/1 pending; web vitest 41/41; mobile jest 50/50; pnpm
typecheck/lint cached green.

2026-05-01 10:30 — tick #64. PR #158 (Phase 4.3) merged at 10:17 UTC.
Picked up Phase 4.4 — mobile review UX. Tiny backend change first:
items endpoint emits `reviews_count: int` per item via one bulk
grouped count (no N+1) so the restaurant page can render an
"X reviews" badge per item without a follow-up roundtrip. Mobile:
new `apps/mobile/lib/api/reviews.ts` with fetchReviews (anonymous,
limit/offset), createReview (multipart for photo or JSON for
text-only — uses RN's {uri,name,type} blob shape that DOM FormData
wouldn't accept), updateReview, deleteReview. Detail screen at
`apps/mobile/app/items/[id].tsx` shows item name + review count +
"Write a review" button + scrollable list of ReviewCards
(★ rating, body, photo). Composer sheet uses expo-image-picker
(library only — Phase 2.6 multi-page CameraView is overkill for one
review photo) with 5-star tap, optional body, optional photo. The
restaurant page got a `<reviewBadge>` per item that pushes
`/items/[id]?itemName=…` via the typed router.push API. Anonymous
write attempt bounces to /login?next=/items/<id>. Tests: 11 new
jest cases covering URL building, query-param presence/absence,
JSON vs multipart switching, 401/403/404 → ReviewError. 1 new rspec
case for the reviews_count field. Local: rspec 229/0/1 pending;
mobile jest 50/50; pnpm typecheck/lint cached green.

2026-05-01 10:00 — tick #63. PR #157 (Phase 4.2) merged at 10:04 UTC.
Picked up Phase 4.3 — review API + photo attachment. The reviews
table existed since Phase 0; this PR wires `has_one_attached :photo`
on the model with size (≤5 MB) + content-type validation
(image/jpeg|png|heic|heif|webp) and ships the four endpoints the
mobile + web review UX needs in 4.4 / 4.5. New ReviewsController:
GET /api/v1/items/:item_id/reviews (public, paginated newest-first
with limit/offset, includes user payload + total), POST same path
(authenticated, multipart for the optional photo, returns
photo_url), PATCH and DELETE on /api/v1/reviews/:id (owner-gated,
403 for non-owners). Photo URL helper builds rails_blob_url against
PUBLIC_HOST when set or request.base_url otherwise — production
deploys point at https://bite-worthy.com. PATCH treats `photo: ""`
as "purge the existing photo." Tests: 16 request specs covering
newest-first ordering, pagination, public access on index, the
404 for unpublished items, auth boundary on create/update/destroy,
photo round-trip via multipart fixture, oversized + wrong-type
rejections, empty-string purge. New review factory at
spec/factories/reviews.rb with realistic body samples. Local: rspec
228/0/1 pending; pnpm typecheck/lint cached green (no JS/TS
changes).

2026-05-01 09:30 — tick #62. PR #156 (Phase 4.1) merged at 09:51 UTC.
Picked up Phase 4.2 — persistent "never hide this dish" override.
Closes the deferred half from Phase 3.4. New `user_item_overrides`
table (user_id, item_id, never_hide bool) with composite unique
index. UserItemOverride model + has_many wires on User + Item;
`User#overridden_items` through-association reads cleanly. New
`POST/DELETE /api/v1/items/:id/never_hide` endpoints (idempotent,
authenticated, 404 for unpublished items). Items endpoint now emits
`overridden_by_user: bool` per item — true only for the
authenticated user's overrides; anonymous always false.
filter-engine: extended `FilteredItem` with optional
`overridden_by_user` and updated `applyOverrides` to union
session + persistent overrides into the visible bucket. Web: new
`/api/items/[id]/never_hide` Next proxy + `setNeverHide` /
`clearNeverHide` client helpers. RestaurantClient gains "Never hide
this dish" sub-action under "Show anyway"; persistent state shows
"Always shown — undo". Mobile: same fetchers + buttons (gated by
`allowPersistent` boolean since the screen still renders anonymously).
Tests: 5 model specs, 6 controller specs, 2 new items-endpoint
specs (auth + anonymous), 4 mobile jest cases for the fetchers,
3 web vitest cases for the helpers, 3 new filter-engine vitest
cases for the persistent override path. Local: rspec 212/0/1
pending; web vitest 30/30; mobile jest 39/39; filter-engine vitest
60/60; pnpm typecheck/lint cached green.

2026-05-01 09:00 — tick #61. PR #155 (Phase 4 plan) merged at 08:47 UTC.
**Major user unblocks during this tick**: ANTHROPIC_API_KEY now in
GitHub Actions secrets + local .env, and bite-worthy.com domain
purchased. Documented as a punch-list response; user requested
continuing the planned flow. Picked up Phase 4.1 — retire the
JWT-paste workaround Phases 1–3 deferred. Web side: new
`apps/web/src/lib/auth.ts` (login/signup/logout client helpers
posting to Next API routes) + `apps/web/src/lib/server-auth.ts`
(`getServerJwt` for SSR cookie reads). Three new Next API routes:
`api/auth/[action]` proxies to Rails + sets HttpOnly bw_session
cookie; `api/profile` PATCH proxies with the cookie's JWT;
`api/ingestion_runs` POST proxies multipart + JSON. New
/login + /signup pages with `?next=…` redirect. Updated /onboarding
+ /ingest to drop JWT input fields; 401s bounce to /login. Mobile
side: `apps/mobile/lib/auth.ts` wrapping expo-secure-store
(getJwt/setJwt/clearJwt + login/signup/logout that pull JWT off
Authorization response header). New /login + /signup screens.
Updated /onboarding + /ingest + /ingest/verify + /restaurants/[id]
to read JWT from keychain instead of paste/query-param. Tests:
9 new vitest cases for auth.ts, 11 new jest cases for the mobile
auth wrapper (round-trip, error fallback, header extraction,
best-effort logout). Existing ingestion + onboarding tests
updated to assert the new proxy URL + no client-side Authorization
header. Two flaky admin specs (admin_spec, dashboard_spec) that
broke when the user's .env set a non-default ADMIN_PASSWORD —
fixed with `around` hooks that pin the env vars during the spec
and restore on teardown. Local: rspec 199/0/1 pending; web vitest
27/27; mobile jest 35/35; pnpm typecheck/lint cached green.

2026-05-01 08:30 — tick #60. PR #154 (Phase 3.9) merged at 08:38 UTC.
**Phase 3 feature-complete** (3.1–3.9 all merged: seeds → mobile
onboarding → mobile restaurant page → transparency chips →
strictness toggle → web restaurant page → applyProfile in
filter-engine → web onboarding → shareable URLs). Per the roadmap's
stated cadence ("After Phase 3 ships, the loop will draft
docs/plans/phase-4.md the same way"), this tick is a plan-update PR:
no code, just `docs/plans/phase-4.md` + the Next-up batch in
`docs/roadmap.md`. Decomposed Phase 4 (reviews + accounts) into 10
PR-sized tasks: 4.1 real session cookies (retire JWT-pasting that
Phases 2+3 deferred); 4.2 persistent "never hide this dish" override
(closes the Phase 3.4 deferred half); 4.3 review API + photo via
ActiveStorage; 4.4 mobile review UX; 4.5 web review UX; 4.6 review
moderation queue (Avo) with hidden_at/hidden_reason + keyword spam
heuristic; 4.7 user profile pages at /u/:handle; 4.8 "My filtered
menus" history via async restaurant_visits log; 4.9 restaurant
claim flow (domain-email verification reusing the suggestions table
with kind:'claim'); 4.10 suggestion queue UX for community edits.
Stop conditions called out: SMTP credentials (mailers), S3 bucket
(review photos), domain-email verification (claim flow). Cross-
cutting notes: telemetry hooks, OpenAPI codegen on every endpoint
PR, JWT-paste comment removal as part of the relevant diff, and the
jest-expo Discovered followup blocking UI snapshots until landed.
Marked Phase 3 ✅ in the roadmap header, captured the "achieved
2026-04-30" demo line. Plan PR awaits human review before items
auto-run, same protocol as the Phase 3 plan PR (#145).

2026-05-01 08:00 — tick #59. PR #153 (Phase 3.8) merged at 07:48 UTC.
Picked up Phase 3.9 — shareable filter URLs. Locked the wire format
in `@biteworthy/filter-engine`: `encodeProfileToken({avoid_ingredient_ids,
avoid_tag_ids, strictness})` produces base64url(JSON({v:1, ai, at, s})),
`decodeProfileToken(token)` parses + validates the whole shape and
throws `InvalidProfileTokenError` on garbage. Built the matching Ruby
implementation at `apps/api/app/services/profile_token.rb` and
asserted byte-identical output via a TS-token fixture in the rspec —
both sides encode the sample payload to the same exact string. Wired
`?profile_token=` on `/api/v1/restaurants/:id/items` (precedence:
profile_token > preset slug > user profile > none); a 422 (with the
"Invalid profile_token: …" body) is returned for malformed/unsupported
tokens. `?strictness=` still overrides what the token encoded so a
strict-mode toggle keeps working on a shared link. Web: extended the
restaurants `[slug]/page.tsx` SSR component to read `?p=` and pass it
through to the items fetch via `profileToken`; the client island
threads the token across every refetch so strictness flips don't
silently drop the encoded profile. Added a `<ShareLinkButton>` (uses
`navigator.clipboard.writeText` with prompt fallback) that turns the
current `filter` summary into `/r/<slug>?p=<token>`. Created the short
`/r/[slug]/page.tsx` route as a pure re-export of the same SSR page.
Mobile: added a Share button using RN's built-in `Share.share`,
extracted the URL-building logic to a pure-TS helper at
`apps/mobile/lib/share-url.ts` for testability. Tests: 12 vitest
(roundtrip + URL-safe + version + 5 error cases + adapter), 10 rspec
service spec (round-trip + Ruby↔TS parity + 5 error cases), 5 controller
specs (profile_token applies, ?strictness override, malformed 422,
future version 422, takes precedence over preset), 4 mobile jest
(roundtrip via decode, URL encoding, default base). Local: rspec
199/0/1 pending; web vitest 21/21; mobile jest 24/24; filter-engine
vitest 57/57; pnpm typecheck/lint cached green. After this PR ships,
Phase 3 is feature-complete and the next tick drafts phase-4.md.

2026-05-01 07:30 — tick #58. PR #152 (Phase 3.7) merged at 07:07 UTC.
Picked up Phase 3.8 — web profile onboarding (mirror of mobile 3.2).
First move: promoted the mobile onboarding reducer into
`@biteworthy/filter-engine` as `onboardingReducer` + `toProfilePayload`
+ `DraftProfile` + `DietaryPreset` + `OnboardingAction`. Mobile reducer
file deleted, mobile screen + API client now import from filter-engine
(rename `reducer` → `onboardingReducer`). 14 reducer tests moved from
mobile jest into filter-engine vitest — mobile jest count drops from
34 to 20, filter-engine grows from 31 to 45. Web pieces: new
`apps/web/src/lib/onboarding.ts` (fetchDietaryProfiles +
searchIngredients + saveProfile, accepts injected fetchImpl);
`apps/web/src/lib/jwt-cookie.ts` (set/get/clear bw_jwt cookie —
plaintext + JS-readable, same workaround the ingest screen uses; Phase
4 swaps for HttpOnly server-managed sessions); 4-step page at
`apps/web/src/app/onboarding/page.tsx` ('use client' for the reducer
+ search + cookie writes). 11 new vitest cases (6 onboarding API
client + 5 cookie helper), no UI snapshot test for the page itself
(same blocker as Phase 3.5 — needs `@testing-library/react` setup).
Local: filter-engine vitest 45/45; web vitest 21/21; mobile jest
20/20; rspec 184/0/1 pending; pnpm typecheck/lint cached green.

2026-05-01 07:00 — tick #57. PR #151 (Phase 3.6) merged at 06:00 UTC.
Picked up Phase 3.7 — consolidated the per-item filter computation
into `@biteworthy/filter-engine`. The package was previously a
prototype with camelCase types that nobody imported; rewrote it
wholesale to be the single TS source of truth for the wire format
the Rails endpoint emits. New surface: canonical types
(`FilterableItem`, `FilteredItem`, `HideReason`, `FilterProfile`,
`LabelLookup`, `ItemSection`, `Strictness`); the `applyProfile`
function (pure, generic over T extends FilterableItem so extra
fields pass through); `buildLabelLookup` (derives ingredient family
from ltree path's first segment, mirroring Rails); display helpers
(`hiddenReasonLabel`, `hiddenReasonHeadline`); section grouping
(`groupItemsBySection`); session-only "show anyway" override
(`applyOverrides`). Migration: deleted `apps/web/src/lib/{hidden-
reason,restaurant-overrides}.ts` + their tests; deleted
`apps/mobile/lib/{hidden-reason,restaurant-overrides}.ts` + tests;
both apps now import the shared helpers + types from filter-engine.
Mobile and web `restaurants` modules keep their fetchers but now
re-export the wire types from filter-engine. Critical addition:
`packages/filter-engine/src/rails-parity.test.ts` runs `applyProfile`
against the same fixture the Rails rspec uses ("Cheese Quesadilla
under vegan preset") and asserts byte-identical output, so a future
drift on either side trips a test. Resolved the helper-consolidation
Discovered followup. Local: filter-engine vitest 31/31; web vitest
10/10; mobile jest 34/34; rspec 184/0/1 pending; pnpm typecheck/lint
green.

2026-05-01 06:30 — tick #56. PR #150 (Phase 3.5) merged at 04:46 UTC.
Picked up Phase 3.6 — web filtered restaurant page (mirror of mobile
3.3 + 3.4 + 3.5). API: extended Restaurant model with
`find_by_id_or_slug!` (sniffs UUID format vs slug); both
`/api/v1/restaurants/:id` and `/api/v1/restaurants/:restaurant_id/items`
now accept either form so SEO-friendly URLs (`/restaurants/cream-bean-
berry-1`) work end-to-end. Web: built `apps/web/src/lib/restaurants.ts`
mirroring the mobile API client (server-callable for SSR), with
duplicates of `hidden-reason.ts` + `restaurant-overrides.ts` for now
(extraction into a shared package logged as Discovered followup).
SSR page at `apps/web/src/app/restaurants/[slug]/page.tsx` fetches
restaurant + initial items in parallel with `notFound()` on miss; the
`'use client'` island `RestaurantClient.tsx` handles strictness
toggle + per-item show-anyway override + chip rendering using
`useTransition` for non-blocking refetch. Tests: 9 vitest for the
API client + grouping; 5 for chip labels; 3 for override
re-bucketing — total 17 new web cases. 4 new rspec cases for the
slug lookup (restaurant by slug + by-slug 404 + draft 404 + items by
slug). Also re-added the Discovered note that lost the auto-merge
race on PR #150 (push-then-second-push was squashed without the
second sha) and added two new Discovered followups (helper
consolidation + auto-merge race protection). Local: rspec 184/0/1
pending; web vitest 21/21; mobile jest 47/47; pnpm typecheck/lint
cached green.

2026-05-01 06:00 — tick #55. PR #149 (Phase 3.4) merged at 04:29 UTC.
Picked up Phase 3.5 — strictness toggle in the restaurant header. The
items endpoint already accepted `?strictness` (Phase 1.7) so this was
mostly a mobile change. Split the screen's effects: restaurant
header loads once per id, items reload whenever id/jwt/strictness
override change. The `<StrictnessToggle>` component renders three
chips (Relaxed / Balanced / Strict); the active chip defaults to
`filter.strictness` (which itself comes from the user profile or the
`?profile=` preset). Tapping a different chip flips
`strictnessOverride` state, which the items effect picks up and
refetches with the new param. Inline ActivityIndicator next to the
chips during refetch; chips are no-ops while loading. The override
clears the per-item "show anyway" set on every refetch — otherwise a
stale id could leak into the visible bucket. Tests: 2 new Jest cases
on the API client (omits param when undefined; passes each strictness
verbatim); 2 new rspec cases on the items endpoint (echoes 'relaxed'
in filter.strictness; ignores garbage values, defense-in-depth for
the toggle). Local: rspec 180/0/1 pending; mobile jest 47/47; pnpm
typecheck/lint cached green.

2026-05-01 05:30 — tick #54. PR #148 (Phase 3.3) merged at 04:22 UTC.
Picked up Phase 3.4 — transparency chips + session-only "show
anyway" override. Backend: `ItemsController#hide_reasons` now
enriches each reason with the human display strings the chip needs
(`ingredient_name` + `ingredient_family` from the ltree path's first
segment; `tag_name` + `tag_family` from the Tag model's family
column). One bulk pluck per kind in `build_label_lookup`, joined to
the items the request already loaded — avoids N+1 even with dozens
of items. The reason payload stays self-contained so the mobile +
web chips never make a second roundtrip. Mobile: pure helper at
`apps/mobile/lib/hidden-reason.ts` formats reasons as "Contains
dairy (Cheese)" / "Tagged allergen: Contains Dairy" / "AI
confidence: suggested (strict mode)" with snake_case → space
humanization (`tree_nut` → `tree nut`) and graceful name/family
fallbacks. Pure helper at `apps/mobile/lib/restaurant-overrides.ts`
re-buckets visible vs hidden based on a `Set<string>` of overridden
ids; preserves section identity for non-touched sections. The
restaurant screen wires both helpers in: every item with reasons[]
gets a Show anyway / Hide again pressable, and the chip row stays
visible after a "show anyway" so the override remains transparent
to the user. The override resets on screen unmount/remount —
Phase 4 introduces the persistent `UserProfile` override. 12 new
Jest cases (6 chip label + 3 headline + 4 override). 1 new rspec
case for the enriched reason payload. Local: rspec 178/0/1 pending;
mobile jest 45/45; pnpm typecheck/lint cached green.

2026-05-01 05:00 — tick #53. PR #147 (Phase 3.2) merged at 03:21 UTC.
Picked up Phase 3.3 — mobile filtered restaurant page. Found a Phase
1.7 gap on the way: `routes.rb` exposed `api/v1/restaurants#index` +
`#show` but no controller existed (every hit would have 500'd with
NameError). Built the minimal `RestaurantsController#show` (id, slug,
name, status, city — what the page header needs) and added a
3-case rspec for it. Also extended `ItemsController#serialize_item`
to include `menu_section_id` + `menu_section_name` so the screen can
group items by menu section without a second roundtrip; added an
`includes(menu_section: :menu)` to dodge N+1. New mobile pieces:
`apps/mobile/lib/api/restaurants.ts` (fetchRestaurant +
fetchRestaurantItems with optional jwt/preset/strictness +
groupItemsBySection helper) and `apps/mobile/app/restaurants/[id].tsx`
(header + filter badge + per-section visible-list + collapsed
"Items hidden by your filter (N)" expander). 11 Jest cases lock down
the API client (anonymous vs JWT, query params) + the section
grouping (server-order preservation, visible/hidden split, "Other"
catch-all). 4 new rspec cases (3 for restaurants#show, 1 for the new
menu_section payload). Local: rspec 177/0/1 pending; mobile jest
32/32; pnpm typecheck/lint cached green.

2026-05-01 04:30 — tick #52. PR #146 (Phase 3.1) merged at 04:18 UTC.
Picked up Phase 3.2 — mobile profile onboarding (6 taps). New API
surface: `GET /api/v1/dietary_profiles` (presets sorted by name with
`avoid_ingredient_ids` + `avoid_tag_ids` inlined so the client can
union picks additively into the draft) and
`GET /api/v1/ingredients?q=&limit=` (ILIKE on name + aliases — the
"garbanzo → Chickpea" alias case has its own spec). Both are public
(skip `:authenticate_user!`) so anonymous users can browse before
sign-up. Mobile work: pure reducer at
`apps/mobile/lib/onboarding-reducer.ts` driving a 4-screen flow
(presets → ingredient search → strictness → review/save). 11 Jest
cases lock down every reducer transition + `toProfilePayload` union
+ dedupe (vegan + dairy-free overlap; stale-slug skip). API client
at `apps/mobile/lib/api/onboarding.ts` accepts injected `fetchImpl`
for test seams. Save on the final step PATCHes
`/api/v1/profile` (Phase 1.3 wholesale-replace). JWT is still pasted
in plaintext — `expo-secure-store` swap is Phase 4 work and matches
the same workaround on the ingest/verify screens. Local: rspec
173/0/1 pending, mobile jest 23/23, pnpm typecheck/lint cached green.

2026-05-01 04:00 — tick #51. Plan PR #145 merged at 01:55 UTC.
Picked up Phase 3.1 — production seeds. Found the existing
dietary_profiles.yml was stale slug-only entries referencing
catalog paths that don't exist post-#131 (`gluten-grain`,
`dairy-milk`, `meat-pork` — the catalog uses `grain-wheat`,
`dairy-cheddar`, `meat-swine-domestic-pig` instead). Extended
`db/seeds.rb` to accept `avoid_ingredient_paths` +
`avoid_tag_paths` lists (ltree subtree match via the GiST `<@`
index — same query Phase 1.7 uses) alongside the existing
slug-exact lists. Rewrote dietary_profiles.yml: 10 presets
(Vegan, Vegetarian, Pescatarian, Celiac, Gluten-Free, Dairy-Free,
Halal, Kosher, Tree-Nut Allergy, Peanut Allergy), each with a
one-line description for the onboarding-card UI. Vegan uses path
prefixes (broad: dairy/egg/meat/poultry/fish/shellfish); Celiac
uses surgical leaves (grain.wheat, grain.rye, grain.barley,
grain.spelt, grain.triticale — not rice/corn/oats). 9 specs cover
catalog shape (10 presets, name + description), idempotence (no
dup join rows), Vegan canary (path-expansion correctness),
Celiac canary (surgical-leaf correctness), Halal canary
(meat.swine + alcohol). Local rspec 166/166 (1 pending), pnpm
checks all cached green. Live seed task ran end-to-end against
the dev DB: 1,096 ingredients + 36 tags + 10 dietary profiles.

2026-05-01 03:30 — tick #50. PR #144 (Phase 2.9) merged at 01:48 UTC.
**Phase 2 feature-complete.** Per the roadmap policy ("After
Phase N ships, the loop pulls Phase N+1 items into Next up via a
plan-update PR"), this tick = plan PR. Drafted
`docs/plans/phase-3.md` decomposing the dietary-filter UI into 9
PR-sized tasks: production seeds (3.1) → mobile onboarding (3.2)
→ mobile restaurant page (3.3) → transparency layer (3.4) → strict
mode toggle (3.5) → web restaurant page (3.6) → applyProfile in
filter-engine (3.7) → web onboarding (3.8) → shareable filter URLs
(3.9). Updated `docs/roadmap.md`: Phase 2 ✅ in phase header,
Next-up replaced with proposed Phase 3 queue. No code changes —
docs-only plan PR for human review before items auto-run.

Ongoing gap from Phase 2: cassette stubs in 2.3 + 2.4 still need
ANTHROPIC_API_KEY to record. Doesn't block Phase 3 (filter UI
works against pre-existing IngestionItems / handcrafted Items)
but does block "live demo with a fresh menu scan."

2026-05-01 03:00 — tick #49. PR #143 (Phase 2.8) merged at 01:18 UTC.
Picked up Phase 2.9 — cost + latency dashboard. New
`Ingestion::CostMetrics` service: aggregates IngestionRun columns
(api_cost_cents/latency_ms/cached+uncached_input_tokens) over
today/last_7_days/last_30_days buckets, computes total_cost,
items_extracted, cost_per_item, avg + p95 latency (nearest-rank),
cache_hit_rate. Target line $0.25/50-item-menu = 0.5¢/item.
New `Admin::DashboardController` (inherits from
ActionController::Base for ERB rendering since the rest of the app
is api_only) at `/admin/dashboard`, gated with the same HTTP Basic
auth Avo uses (re-reads ADMIN_USERNAME/ADMIN_PASSWORD ENV).
Self-contained ERB layout with three period cards, color-coded
cost-per-item warning when above the 0.5¢ target, color-coded
cache-hit rate. Bug caught locally: my period_label_for computed
days from `(end - begin) / 1.day` and the half-day tail rounded
7→8 → restructured PERIODS to carry explicit labels. 8 metric
specs (totals, zero-safety, zero-items no-divide, percentile +
edge cases) + 3 dashboard request specs (auth challenge / wrong
creds / right creds renders metrics). Local rspec 157/157
(1 pending), pnpm typecheck/lint/test all green.

**Phase 2 feature-complete after this merges.** Next tick will draft
the phase-3 plan PR (same pattern as #135).

2026-05-01 02:25 — tick #48. PR #142 (Phase 2.7) merged at 00:48 UTC.
Picked up Phase 2.8 — web URL/PDF entrypoint. New `UrlFetcher`
service: faraday GET with 15s timeout, 10MB max bytes, sniffs PDF
magic bytes when content-type is missing, raises
`UrlFetcher::FetchError(reason:, status:)` on non-2xx / oversize /
invalid scheme. Updated `Api::V1::IngestionRunsController#create`
to branch on `inputs[]` (multipart) vs `source_url` (URL-fetch
path), populating `input_kind` (url|pdf) accordingly. Bug caught
locally: `File.basename("/")` returns `"/"` → my filename
fallback produced `"/.html"` instead of `"menu.html"`.

Web: `apps/web/src/lib/ingestion.ts` exposes `ingestFromUrl`
(JSON body) + `ingestFromFile` (multipart FormData) + a typed
`IngestionRequestError`. New page at `apps/web/src/app/ingest/page.tsx`
('use client', Tailwind-styled): restaurant_id + JWT inputs +
two side-by-side panels (URL submit / file dropzone), success
panel links to `/admin/resources/ingestion_runs`.

Specs: 7 URL-fetcher specs (header content-type, magic-byte sniff,
404 + oversize + invalid-scheme rejection, filename inference) +
3 new controller specs (URL happy path HTML, URL happy path PDF,
422 on upstream non-2xx) = 10 new Rails specs. 4 web vitest tests
(ingestFromUrl POST shape + error, ingestFromFile multipart +
non-JSON error path).

Local: rspec 146/146 (1 pending), pnpm typecheck/lint/test all
green. Pushing PR.

2026-05-01 01:45 — tick #47. PR #141 (Phase 2.6) merged at 00:22 UTC.
Picked up Phase 2.7 — swipe-verify UI + ingestion-item PATCH/INDEX
endpoints. API: new `Api::V1::IngestionItemsController` with #index
(list run's items) + #update (PATCH decision). Update validates
decision ∈ {pending,accepted,rejected,edited}, applies edit overrides
(name/description/payloads) before promote!, fires
maybe_publish! after every decision. Routes nested under
`ingestion_runs/:run_id/items`. Bug caught locally:
`ActionController::Parameters` doesn't have `#any?` — switched to
`params.to_h.any?`. 10 request specs covering happy/edit/reject/
auth/validation/threshold-trigger paths.

Mobile: extended `lib/api/ingestion-runs.ts` with `getIngestionRun`,
`listIngestionItems`, `decideIngestionItem`. New screen
`app/ingest/verify.tsx`: polls run state every 2s while
extracting/resolving, opens a one-card-at-a-time deck on :staged,
Accept/Edit/Reject buttons with full decision wiring. Deferred:
Tinder-style swipe gestures (gesture-handler/reanimated) — the
data wiring is what matters for end-to-end; gestures are pure
visual sugar best added during on-device polish. 5 new Jest tests
(decideIngestionItem PATCH shape + edits + error path,
getIngestionRun, listIngestionItems).

Local: rspec 136/136 (1 pending), pnpm typecheck/lint/test all
green. Pushing PR.

2026-05-01 01:00 — tick #46. PR #140 (Phase 2.5) merged at 23:49 UTC.
Picked up Phase 2.6 — mobile camera + upload. Two surfaces in one PR:

API: `Api::V1::IngestionRunsController#create + #show`. Create
gates on `is_admin?`, requires multipart `inputs[]` files, attaches
to ActiveStorage `inputs`, fires `transition_to!(:extracting)`
(which dispatches ExtractMenuJob via JOB_FOR). Show is owner-or-
admin gated. Auto-detects pdf vs photo from content_type. New
routes under `api/v1`. 10 request specs (happy/auth-gate/unknown
restaurant/no inputs/PDF/show owner/show admin/show stranger/show
unauth) + 2 rswag schema specs.

Mobile: `lib/api/ingestion-runs.ts` — `uploadIngestionRun({
restaurantId, pages, jwt })` builds multipart FormData via React
Native's Blob-shape. `IngestionUploadError` carries status + body.
4 Jest tests (POST shape, error path, empty-pages guard, non-JSON
body survives). New screen at `app/ingest/index.tsx` with
restaurant_id + JWT inputs, expo-camera flow with capture
button (production capture-via-ref deferred), thumbnail strip
with long-press delete, "Upload all" button. Uses ui-tokens
(colors.bgAlt for thumb backgrounds, etc.). Added @types/jest +
@types/node + tsconfig types entry so Jest globals are typed.

Local: rspec 126/126 (1 pending), pnpm typecheck/lint/test all
green, codegen drift clean (regenerated openapi.json + generated.ts).
Pushing PR.

2026-05-01 00:15 — tick #45. PR #139 (Phase 2.4) merged at 23:20 UTC.
Picked up Phase 2.5 — admin verify UI + auto-publish threshold.
Generated Avo resources for IngestionRun + IngestionItem (Phase 1.5
shipped without them — they only got generated for the data-model
set explicitly in phase-1.md §1.5). Customized both: badge fields
for status + decision; panels grouping pipeline / cost / AI extraction
/ AI suggestions / unresolved; staging + raw_output as JSON code
viewers. Three Avo Actions: `IngestionRuns::ReExtract` (resets
state_history + staging, dispatches ExtractMenuJob), `IngestionItems
::Accept` (calls IngestionItem#promote!, runs maybe_publish! after),
`IngestionItems::Reject` (sets decision, runs maybe_publish! after).
Action handle methods extracted into class methods (`accept_all`,
`reject_all`) so specs can exercise them without Avo's controller
lifecycle (which wires `succeed`). New `IngestionRun#maybe_publish!`:
publishes the run + restaurant when ≥80% of decided items are
accepted; pending items don't count toward the denominator. 9 new
specs (6 publication-threshold + 3 Avo accept-action). Local rspec
116/116 (1 pending). Pushing PR.

2026-04-29 23:50 — tick #44. PR #138 (Phase 2.3) merged at 23:14 UTC.
Picked up Phase 2.4 — Resolve jobs. Same ANTHROPIC_API_KEY stop
condition handled the same way as 2.3 (mocked-client coverage,
cassette deferred). New: migration adds `unresolved_tags :jsonb`
to ingestion_items (mirrors existing unresolved_ingredients).
`Ingestion::ResolutionSchema` (shared JSON Schema for both jobs:
`{items: [{index, resolved: [{slug, confidence}], unresolved: [str]}]}`).
`Ingestion::CatalogBuilder` renders Ingredient + Tag tables as
`slug | name | (path) | aliases` text — the bulk of input tokens,
goes in the cached system block. `Ingestion::ResolveIngredientsPrompt`
+ `ResolveTagsPrompt` build cached system blocks per resolution.
`ResolveIngredientsJob` walks staging items, calls Anthropic, writes
`ingredients` + `unresolved_ingredients` arrays back into staging,
chains to `ResolveTagsJob`. `ResolveTagsJob` does the same for tags
THEN materializes IngestionItem rows + transitions to :staged.
10 mocked-client specs (5 ingredients, 5 tags) + 1 cassette stub
(deferred) covering happy path, no-items, ApiError, ValidationError,
no-op on terminal states, IngestionItem creation. Local rspec
107/107, 1 pending. Pushing PR.

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
