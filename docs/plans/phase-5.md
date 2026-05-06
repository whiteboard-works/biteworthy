# Phase 5 — Launch (subplan)

Phase 1 → 4 + 4.11 turned the codebase into a working product running on a developer laptop. Phase 5 turns it into something a real person in Durango can open on a Friday night and use to pick where to eat. The work splits into three buckets:

1. **Production deploys** — API, web, mobile bundles all need a real public home plus the storage / email / blob infra they were stubbing in dev.
2. **Public-facing surface** — marketing landing, SEO city pages, press kit. Today the web app's `/` is "hello"; nobody can find the product.
3. **Seed data + launch motion** — 30 real Durango restaurants ingested, store submissions, instrumentation, outreach.

**Demo at the end (the real one):** a real user in Durango opens bite-worthy.com on Friday at 6pm, picks "Celiac + tree-nut allergy", taps the nearest of 30 seeded restaurants, sees only the dishes that are safe, walks in and orders.

## Stop conditions specific to Phase 5

This phase has the most external-dependency surface of any phase so far. The loop's discipline is to ship the *wiring* and flag what needs a human credential or signature.

- **Anthropic production billing** — the daily-cap reset that's blocked Phase 4.11.0 / 4.11.2-cassette is the same surface that limits a 30-restaurant ingest. The loop should NOT mass-ingest until a human confirms the project tier supports the run cost (~$10–15 for 30 menus at the Phase 2.9 dashboard's measured rates).
- **SMTP credentials** — the Phase 4 stop condition still applies. Phase 5.2 picks a provider (recommend SES or Postmark), wires the env vars, ships an `bin/rails email:smoke` task. Live-send needs a human to drop creds in `.env.production`.
- **S3 / R2 bucket** — Phase 2 + 4 deferred this. Phase 5.3 wires it; bucket creation + IAM + CORS need a human.
- **App Store / Play Store team accounts** — Apple Developer Program ($99/yr) + Google Play Console ($25 one-time) need a human signature. EAS submit can drive the upload once credentials exist.
- **Apple review timeline** — typically 1–7 days. Not blocking the loop but a real launch dependency. Submit early.
- **Real menu PDFs / URLs for 30 Durango restaurants** — research task, not a coding task. The loop ships the batch-ingest tooling + a `seeds.csv` template; populating it is human work. (`docs/seeds/durango.csv.example` will list the columns.)
- **DNS for bite-worthy.com** — domain is registered. Once the API host (5.1.1) + web host (5.4) are picked, DNS records need a human in the registrar.
- **Hetzner + Neon + GHCR accounts** (per 5.1.1) — Hetzner Cloud account for the CX22, Neon account for managed Postgres, a GitHub PAT with `write:packages` for the GHCR push. None individually is more than a 5-minute signup; collectively they replace the single Fly account from the original 5.1 plan.
- **Privacy policy + terms** — App Store requires both. Phase 5.9 ships standard templates filled with BiteWorthy specifics; a human should have a lawyer skim before submission.

## Tasks (one PR each)

### 5.1 — Production API deploy: Fly.io + Postgres + Solid Queue

**Branch**: `claude/phase-5.1-api-deploy`

The Rails API needs a real public home so the mobile + web apps can hit something other than `localhost:3000`.

- Pick Fly.io (Rails-friendly defaults, Solid Queue worker process is straightforward, predictable bill). Alternatives: Render, Railway. Decision recorded in a new `docs/adr/0002-production-hosting.md`.
- `fly.toml` at `apps/api/`. Two processes: `web` (puma) + `worker` (`bin/jobs`). Postgres via `fly postgres create` (start with the cheapest dev tier; rotate to a real plan when seed data is in).
- Required env: `RAILS_MASTER_KEY`, `DATABASE_URL`, `PUBLIC_HOST=https://api.bite-worthy.com`, `ANTHROPIC_API_KEY`, the omniauth + devise secrets from Phase 1.2. ADR documents the source of each.
- Smoke task: `bin/rails biteworthy:production:smoke` hits `/up`, posts a no-op IngestionRun, fetches it back. Run it from CI on every deploy.
- DNS: `api.bite-worthy.com` CNAME to the Fly app. Documented but human-applied (see Stop conditions).

**Specs**: smoke task spec; existing rspec stays unchanged (same env shape).

**Acceptance**: `curl https://api.bite-worthy.com/up` returns 200 from a fresh checkout.

> **Superseded by 5.1.1.** The Fly.io pick was reversed at human request before the live deploy happened. The wiring shipped in PR #172 (Dockerfile, smoke task, env docs) is largely reusable; only the `fly.toml` + Fly-specific README sections get replaced. ADR 0002 will be marked superseded by ADR 0007.

### 5.1.1 — migrate API hosting to Kamal + Hetzner CX22 + Neon Postgres

**Branch**: `claude/phase-5.1.1-kamal-migration`

Replaces Phase 5.1's Fly.io pick. Same goal — get the Rails API publicly reachable at `api.bite-worthy.com` — different stack:

- **Compute**: 1 × Hetzner **CX22** (4GB RAM / 2 vCPU / ~€5/mo) in the **Ashburn, US** datacenter (`ash`). Both puma + Solid Queue worker run on the same box as separate Kamal **roles** (`web` + `worker`). Tier up to CX32 or split the worker to a second box only if launch volume reveals headroom issues — the CX22 has more spec than the dual-Fly-machine setup it replaces, at lower cost.
- **Postgres**: **Neon** (managed, free tier, branching, `aws-us-east-1`). Free tier covers Durango beta easily; bumps cost only past 0.5 GB or compute-hour limits. The app box stays stateless — rebuilding it never risks data, no `pg_dump` cron needed. Neon handles backups (7-day retention, free).
- **Container deploys**: **Kamal** (Basecamp's). Zero-downtime via Traefik, automatic Let's Encrypt TLS, single-command rollback. Image registry: **GitHub Container Registry (`ghcr.io`)** since the repo is already in `whiteboard-works/` — same auth model, free for private repos.

**What stays from PR #172** (no changes needed):
- The multi-stage `apps/api/Dockerfile` — Kamal uses the same OCI image.
- `apps/api/bin/docker-entrypoint` — same db:prepare-on-puma logic.
- The `Biteworthy::ProductionSmoke` runner + `bin/rails biteworthy:production:smoke` task — they hit a public URL regardless of host.
- All of Phase 5.2 (SMTP), 5.3 (R2 storage), 5.4 (Vercel web), 5.5–5.10. Orthogonal.

**What this PR changes**:
- **Delete** `apps/api/fly.toml`.
- **Add** `apps/api/config/deploy.yml` — Kamal's canonical config: app name, server IP placeholder, `web` + `worker` roles pointing at the same image, registry block for GHCR, Traefik labels for Let's Encrypt, healthcheck on `/up`, env-var passthrough.
- **Add** `apps/api/.kamal/secrets.example` — template for `KAMAL_REGISTRY_PASSWORD` (GHCR token), `RAILS_MASTER_KEY`, `DATABASE_URL` (Neon pooled URL), `ANTHROPIC_API_KEY`, the rest of the existing prod env. Real `.kamal/secrets` is gitignored.
- **Update** `apps/api/.env.example` — drop the Fly-specific section, add a Kamal/Hetzner/Neon section with the env vars and where they come from.
- **Update** `apps/api/README.md` "Production deploy" — replace the `fly` commands with `kamal setup` / `kamal deploy` / `hcloud server create` flow. Keep the smoke command.
- **Add** `docs/adr/0007-hosting-kamal-hetzner-neon.md` — captures the decision: why Kamal over Fly, why Hetzner CX22 over (Render / Railway / Coolify / DIY), why Neon over (Hetzner-Postgres-on-same-box / Supabase / RDS), why GHCR over (Docker Hub / self-hosted), trade-offs (you own the host's OS updates) + mitigations (cheap snapshots, automated security updates).
- **Update** `docs/adr/0002-production-hosting.md` — change Status to `Superseded by 0007 (2026-04-30)` + a one-paragraph note pointing at 0007.

**Specs**: no new test surface. The smoke task spec from #172 stays; config files don't need unit coverage.

**Acceptance**: same as 5.1 — `curl https://api.bite-worthy.com/up` returns 200 after the human bootstrap.

**Stop conditions specific to 5.1.1**:
- **Hetzner Cloud account** — sign up at https://hetzner.cloud, generate an API token, install `hcloud` CLI locally OR provision via the web console.
- **Neon account** — sign up at https://neon.tech, create a `biteworthy-prod` project in `aws-us-east-1`, copy the **pooled** connection string (the unpooled one will exhaust connections under puma+worker concurrency).
- **GHCR access token** — GitHub → Settings → Developer Settings → Personal Access Tokens (classic) → generate one with `write:packages` + `read:packages` scopes; store as `KAMAL_REGISTRY_PASSWORD` in `.kamal/secrets`.
- **SSH keypair** — generate ed25519, add public key to Hetzner's "SSH keys" panel BEFORE provisioning the CX22 (saves a console-bound password reset).
- **DNS** — `api.bite-worthy.com` `A` record at the Hetzner IP. Same registrar work as the original Fly plan.

**Human bootstrap** (rewrite of the README's "Production deploy" section):

```bash
# 1. Provision the box (Hetzner Cloud Console or `hcloud`).
hcloud server create \
    --name biteworthy-api \
    --type cx22 \
    --image ubuntu-24.04 \
    --datacenter ash-dc1 \
    --ssh-key skylar
# Note the IP. Set the `api.bite-worthy.com` A record to it.

# 2. Set up Kamal locally (one-time).
gem install kamal
cd apps/api
cp .kamal/secrets.example .kamal/secrets
# Fill in the real values: GHCR token, RAILS_MASTER_KEY,
# DATABASE_URL (Neon pooled), ANTHROPIC_API_KEY, ADMIN_*,
# DEVISE_JWT_SECRET_KEY, OAuth secrets, SMTP_*, R2_*, MAILER_HOST.

# 3. First deploy.
kamal setup            # installs Docker on the box, pulls image, boots Traefik
kamal env push          # uploads `.kamal/secrets` to the box
kamal deploy            # full deploy with db:prepare release command

# 4. Confirm.
bin/rails biteworthy:production:smoke HOST=https://api.bite-worthy.com EXIT_CODE=1
```

Subsequent deploys: `kamal deploy` from the laptop. CI automation deferred to a separate small follow-up PR (cleaner to verify manual deploys work first).

**Out of scope for 5.1.1**:
- Multi-region (single Ashburn box for v1).
- Postgres-on-Hetzner (Neon handles DB; revisit only if Neon ever bites cost-wise).
- Phase 5.4 (Vercel for web) — explicitly kept per the human's directive.
- CI-driven `kamal deploy` on master push — separate small PR after the manual flow is proven.

### 5.2 — SMTP wiring (real email for reviews + claims + password resets)

**Branch**: `claude/phase-5.2-smtp`

Phase 4.3 / 4.6 / 4.9 all stubbed mailers with `:test` adapter. Production needs real delivery.

- Pick Postmark (best deliverability for transactional, generous free tier). Alternatives: SES (cheaper at scale but more wiring), SendGrid. Decision in ADR.
- `config/environments/production.rb` switches `action_mailer.delivery_method = :smtp` with creds from `SMTP_*` env vars.
- All existing mailer templates render-tested against a real Postmark sandbox. Layout pulled from `_legacy/` if anything reusable; otherwise plain text + minimal HTML.
- `bin/rails email:smoke` task that posts one of each kind (review confirmation, claim verification, password reset) to a configurable address and reports the Postmark message-id.

**Specs**: ActionMailer test envs prove the templates render with the expected variables; live-send is a manual smoke per Stop conditions.

**Acceptance**: a human runs `email:smoke EMAIL=skylar@…` and receives all three.

### 5.3 — ActiveStorage S3 / R2 (review + dish photos in production)

**Branch**: `claude/phase-5.3-blob-storage`

Phase 2 + 4 + 4.11 all noted that local-disk ActiveStorage is fine in dev/CI but production needs real object storage. This is that PR.

- Pick Cloudflare R2 (S3-compatible, no egress charges — meaningful for image-heavy traffic). Falls back to AWS S3 with no code changes if the human prefers. Decision in ADR.
- `config/storage.yml` gains `:r2` (and keeps `:amazon` for the fallback). `production.rb` flips `active_storage.service = :r2`.
- Required env: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_ENDPOINT`. Documented in `.env.example`.
- One small change to `ReviewsController#photo_url_for` + the equivalent in `ItemsController` (Phase 4.11.3): the signed URL now points at R2's public endpoint rather than `request.base_url`. PUBLIC_HOST env var still drives the production host.
- Backfill task: `bin/rails biteworthy:storage:backfill` re-uploads any local-disk attachments to R2 (no-op if already on R2). Idempotent.

**Specs**: ActiveStorage URL helpers in test mode unchanged; the only new spec is the backfill task's idempotence on already-migrated blobs.

**Acceptance**: a review photo posted via mobile in production survives a server restart and renders on the web restaurant page.

### 5.4 — Production web deploy: Vercel + bite-worthy.com

**Branch**: `claude/phase-5.4-web-deploy`

- Pick Vercel (Next.js native, free tier handles a Durango-scale beta). Alternative: Cloudflare Pages. ADR.
- `apps/web/vercel.json` if any custom routing is needed; default Next.js detection should suffice.
- Env: `NEXT_PUBLIC_API_BASE=https://api.bite-worthy.com`. Cookie domain set to `.bite-worthy.com` so the JWT cookie from Phase 4.1 works across `www` + `app` if we add a subdomain later.
- DNS: `bite-worthy.com` apex to Vercel + `www.bite-worthy.com` CNAME. Human-applied per Stop conditions.
- `robots.txt` allows everything; `sitemap.xml` generated from `app/sitemap.ts` covers `/`, `/durango/[diet]` (5.6), and the seeded restaurant pages.

**Specs**: vitest for the sitemap generator; smoke that the `/up` proxy from web → API resolves.

**Acceptance**: `https://bite-worthy.com` resolves to the marketing landing and the SSR restaurant pages work.

### 5.5 — Marketing landing page at `/`

**Branch**: `claude/phase-5.5-landing`

The current root is a leftover "hello" page. Replaces it with a real first impression.

- Hero: "See only the dishes you can eat." Subhead explains the dietary filter in one sentence. CTA buttons: "Get the iOS app", "Get the Android app", "Try the web app" (deeplinks to App Store / Play Store / `/restaurants`).
- Three-up feature explainer: scan menu → pick filter → see safe dishes. Each with a screenshot from a real seeded restaurant page.
- Footer: privacy, terms, press, GitHub link, Durango focus statement.
- Pure SSR — no client islands needed. Tailwind-only. Reuses `@biteworthy/ui-tokens` colors so the brand stays consistent with the apps.
- Open Graph + Twitter card meta tags so shared links look right.

**Specs**: vitest for the meta-tag composition (deterministic strings). Visual review on a deployed preview.

### 5.6 — SEO landing pages: `/durango/[diet]`

**Branch**: `claude/phase-5.6-city-diet-pages`

Parameterized routes that index well for "celiac restaurants Durango", "vegan Durango", etc. — the actual queries Durango folks already type.

- Route: `app/durango/[diet]/page.tsx`. `[diet]` is a slug from `DietaryProfile`; 404 if unknown.
- SSR fetches the 30 seeded restaurants, applies the preset's filter on the server, ranks by `(visible_count desc, name asc)`. Each row shows: restaurant name + neighborhood + count of visible items + a "see menu" deep link.
- Per-page meta: `<title>Vegan restaurants in Durango — BiteWorthy</title>`, og:image generated server-side (a static template with the diet name overlaid; can be hand-polished later).
- `sitemap.ts` enumerates one URL per active dietary preset.

**Specs**: vitest for the ranking + filtering logic; request-spec smoke for the 30-restaurant payload.

**Acceptance**: Google's mobile-friendly tester gives `/durango/gluten-free` a passing grade after deploy.

### 5.7 — Seed 30 Durango restaurants via the ingestion pipeline

**Branch**: `claude/phase-5.7-durango-seed`

Operator-driven batch ingest. The pipeline already works (Phase 2 + 4.11); this PR adds the workflow for running it 30 times from a CSV.

- New `docs/seeds/durango.csv.example`: columns `name`, `address`, `phone`, `website`, `menu_source` (URL or local PDF path), `neighborhood`. Real seeding lives in a private repo + uses an unchecked `durango.csv`.
- `bin/rails biteworthy:seed:durango FILE=durango.csv`: each row creates a `Restaurant`, kicks off an `IngestionRun` (URL or PDF entrypoint per Phase 2.8), polls until staged-or-failed, prints a status line. Reuses Phase 2.9's cost dashboard for the per-run accounting.
- New Avo dashboard tile: "Durango seed run" — running totals of staged / published / failed across the batch.
- The run does NOT auto-publish — the 80%-accepted threshold from Phase 2.5 still gates publication via the swipe-verify queue. A human still verifies each menu before it goes live.

**Specs**: rake task spec with a small CSV fixture (3 fake restaurants, fully mocked Anthropic); Avo tile spec.

**Acceptance**: running the task against the real CSV ends with 30 staged runs in `/admin/dashboard`, all under the projected $15 budget.

### 5.8 — PostHog funnel wiring (real instrumentation)

**Branch**: `claude/phase-5.8-posthog`

Phase 3 + 4 emitted placeholder `track(...)` events; this lights them up.

- Picks PostHog Cloud (generous free tier for a launch; self-host later if volume warrants). ADR notes the trade-off vs Plausible / Mixpanel.
- New `lib/track.ts` (web) + `lib/track.ts` (mobile): thin wrapper around `posthog-js` / `posthog-react-native`. `track(eventName, props)` no-ops in dev unless `POSTHOG_KEY` is set; honors `Do-Not-Track` and the in-app analytics toggle (new on `/profile/settings`).
- Funnel events instrumented end-to-end: `app_open`, `profile_set`, `menu_filtered`, `restaurant_tap`, `filter_changed`, `review_posted`, `share_link_copied`, `restaurant_claimed`, `suggestion_submitted`. Each has a stable name + a documented payload schema in `docs/analytics.md`.
- Server-side: `RecordRestaurantVisitJob` (Phase 4.8) doubles as the source of `restaurant_tap` for authenticated users so the funnel stays right even when JS analytics is blocked.

**Specs**: unit tests for the wrapper (DNT respected, settings toggle respected, payload shape stable); fake `posthog` client.

**Acceptance**: a real beta tester completes the full funnel; PostHog dashboard shows the conversion at each step.

### 5.9 — Mobile app store submission (TestFlight + Play Store)

**Branch**: `claude/phase-5.9-app-stores`

- App icon + splash assets generated from `@biteworthy/ui-tokens` colors. Output to `apps/mobile/assets/` at the sizes Expo's `app.json` expects.
- App Store + Play Store metadata in `apps/mobile/store-listing/`: name, subtitle, description, keywords, screenshots (5+ per device class). Screenshots scripted via `expo-router` test routes that drive the seeded restaurants from 5.7.
- Privacy policy + terms — boilerplate templates in `apps/web/src/app/{privacy,terms}/page.tsx` (linked from the marketing landing 5.5 + the App Store submission). Filled with BiteWorthy-specific data flows; a human + lawyer should final-review.
- EAS config: `eas.json` with `production` profile pointed at the App Store + Play Store build channels. `eas submit --platform=all` driven from CI on tag.
- Initial submission is for **TestFlight beta** + **Internal Testing track**, NOT public release. Public release is gated on ~50 internal-tester sessions clean.

**Specs**: pure-TS test for the screenshot-driver routes (URL composition); no end-to-end EAS test (that's a paid build).

**Acceptance**: a beta link from TestFlight reaches at least 5 testers; one full week with no crash reports clears the path to public release.

### 5.10 — Press kit + outreach (Durango launch)

**Branch**: `claude/phase-5.10-press`

- `/press` page on web: logo lockup (PNG + SVG), screenshots, a 50-word + 200-word product blurb, founder bio + photo, contact email, recent app store links.
- Email templates in `docs/outreach/` for Durango press: Durango Telegraph, Durango Herald, La Plata Mountaineer, Local KSUT FM. One template per outlet shaped to their beat (Telegraph: dining; Herald: tech; KSUT: human-interest).
- Soft-launch waitlist on the marketing landing (5.5): email-only form, stores in a new `waitlist_signups` table, sends a "you're on the list" confirmation via the 5.2 SMTP wiring. Emails get an "early access" blast 48h before public release.
- Launch-day social posts staged in `docs/outreach/launch-day.md` (Twitter/X, Bluesky, Instagram, LinkedIn). Hashtag plan: `#Durango`, `#GlutenFree`, etc.

**Specs**: request spec for the waitlist endpoint; vitest for the email-validation helper.

**Acceptance**: at least three Durango outlets confirm they'll cover launch; the press page passes Lighthouse 95+ on mobile.

## Cross-cutting

- **OpenAPI codegen** — every new endpoint (`GET /api/v1/durango/restaurants`, the waitlist post) regenerates `packages/api-types/src/generated.ts` per the Phase 1.6 pipeline.
- **Cost dashboard** — Phase 2.9's `/admin/dashboard` already tracks per-run Anthropic spend. Phase 5.7 + 5.8 add a "production health" tab: deploy status (5.1 / 5.4 healthchecks), error rate from PostHog, weekly active filter sessions.
- **Discovered followups** — the existing `jest-expo` + `@testing-library/react` items remain in the queue. Phase 5.5 / 5.6 / 5.10 will add to that list if more JSX-render coverage gaps appear; the loop should keep these as standalone PRs rather than bundling.
- **Auto-merge race** — the prior Discovered note about PR #150 stays open. Phase 5 has shorter PR cycles (deploys + content), so the race is more likely; consider gating auto-merge on a manual `ready-to-merge` label after the final push if a second occurrence happens.

## Out of scope for Phase 5 (explicit)

- **Stripe / payments** — no monetization in v1. Premium tier is a Phase 6+ conversation.
- **Push notifications** — Phase 4 explicitly out-of-scoped this. Same here.
- **Reservations / delivery integrations** — out per `docs/roadmap.md`.
- **Cities outside Durango** — Phase 6+ gates expansion on the Durango funnel hitting a target conversion rate.
- **Native iOS / Android codebase split** — Phase 0 ADR already ruled this out.
- **Restaurant photo galleries** — `has_one_attached :photo` (Phase 4.11.3) ships one photo per dish; multi-photo galleries are Phase 6+.
- **Social graph / feed / gamification** — explicitly NOT in v1 per the roadmap's NOT-doing list.
