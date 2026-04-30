# Launch readiness — what's done, what's left for the human

Snapshot at the end of tick #88 (2026-04-30 22:51 UTC). After PR #183 merged, **every loop-shippable Phase-5 piece is on master**. The remaining work is entirely human-gated: credentials to drop, accounts to create, one cassette to record, one lawyer pass.

The loop pauses here. The next tick (post-Anthropic-cap-reset at 2026-05-01 00:00 UTC) will attempt the cassette retry. Other items wait for human action.

## What's on master right now

### Backend (Rails 8 API, `apps/api/`)

- Auth: Devise + JWT + OAuth (Apple, Google) — Phase 1.1, 1.2.
- Profile + history endpoints — Phase 1.3, 4.8.
- Curated taxonomy: 1,096 ingredients + tag tree + 8 dietary presets — Phase 1.4, 3.1.
- Avo `/admin` with HTTP-basic gate — Phase 1.5.
- OpenAPI codegen pipeline — Phase 1.6.
- Restaurant + Item read endpoints with the full filter — Phase 1.7.
- AnthropicClient + ExtractMenuJob + ResolveIngredients/Tags + IngestionRun state machine — Phase 2.1–2.4. Cassettes are mocked; live recording is the only outstanding Phase 2 work.
- Admin verify UI + 80%-accepted publish — Phase 2.5.
- Mobile camera ingest + URL/PDF web entrypoint — Phase 2.6, 2.8.
- Cost + latency dashboard at `/admin/dashboard` — Phase 2.9.
- Reviews API + photos + moderation queue + reviews on item — Phase 4.3–4.6.
- Public user profiles + history visits — Phase 4.7, 4.8.
- Restaurant claim flow + suggestion queue — Phase 4.9, 4.10.
- Per-dish photo extraction (cropper service, Item.has_one_attached :photo, materialize, schema+prompt extension for vision bboxes) — Phase 4.11.1, .2, .3, .4.
- Cities ranking endpoint at `/api/v1/cities/:slug/restaurants?profile=:diet` for the SEO pages — Phase 5.6.
- Durango batch ingest task at `bin/rails biteworthy:seed:durango FILE=…` — Phase 5.7.
- Production smoke at `bin/rails biteworthy:production:smoke` — Phase 5.1.
- Production SMTP (Postmark) + email smoke task — Phase 5.2.
- Production storage on Cloudflare R2 + idempotent backfill task — Phase 5.3.
- Waitlist signup endpoint + confirmation mailer — Phase 5.10.
- Kamal deploy config (`config/deploy.yml` + `.kamal/secrets.example` + `.kamal/hooks/pre-deploy`) — Phase 5.1.1.
- 377 rspec examples passing.

### Web (Next.js 15, `apps/web/`)

- Marketing landing at `/` + waitlist form — Phase 5.5, 5.10.
- SEO city/diet pages at `/durango/[diet]` (8 curated diets, build-time pre-render) — Phase 5.6.
- Filtered restaurant pages with strictness toggle, show-anyway, never-hide, share-link, reviews — Phases 3.6, 3.7, 3.8, 3.9, 4.1, 4.2, 4.5.
- User profiles, history, ingest URL/PDF entrypoint — Phases 4.7, 4.8, 2.8.
- Onboarding (6-tap profile) — Phase 3.8.
- /privacy, /terms, /press — Phases 5.9, 5.10.
- Sitemap + robots, Vercel config, cookie-domain helper — Phase 5.4.
- Analytics abstraction wired (no-op until Phase 5.8-wiring injects posthog-js) — Phase 5.8.
- 99 vitest passing.

### Mobile (Expo SDK 52, `apps/mobile/`)

- Onboarding (6-tap profile) + login/signup with secure-store — Phases 3.2, 4.1.
- Filtered restaurant page with show-anyway, never-hide, strictness toggle, hidden-reason chips, dish photos — Phases 3.3, 3.4, 3.5, 4.2, 4.11.4.
- Camera + photo-library ingest, swipe-verify queue — Phases 2.6, 2.7.
- Reviews UX, history, public user pages — Phases 4.4, 4.7, 4.8.
- Suggestion submission flow — Phase 4.10.
- Store-listing markdown templates + eas.json + assets/README — Phase 5.9.
- Analytics abstraction wired (no-op until Phase 5.8-wiring injects posthog-react-native) — Phase 5.8.
- 60 jest passing (all lib-only — UI snapshots gated on the jest-expo Discovered followup).

### Shared packages (`packages/`)

- `@biteworthy/api-types` — handwritten until Phase 1.6's codegen lands.
- `@biteworthy/filter-engine` — pure-TS dietary filter, mirrors the SQL — Phase 3.7.
- `@biteworthy/ui-tokens` — design tokens for Tailwind + RN StyleSheet.
- `@biteworthy/eslint-config` — minimal flat config.
- `@biteworthy/analytics` — Tracker abstraction + EVENTS taxonomy + noop — Phase 5.8.

## What you (the human) need to do

Numbered roughly in dependency order. Each step lists what it unlocks.

### 1. Provision the Rails API (Phase 5.1.1)

**Unlocks:** every API-dependent flow (the web app's API calls, the mobile app's calls, the seed task).

```bash
# Hetzner
hcloud server create --name biteworthy-api --type cx22 \
    --image ubuntu-24.04 --datacenter ash-dc1 --ssh-key skylar
# Note the IP. DNS: api.bite-worthy.com A → that IP.

# Neon: sign up at neon.tech, create biteworthy-prod in
# aws-us-east-1, copy the POOLED connection string.

# GHCR: GitHub → Settings → Developer settings → PAT (classic)
# with write:packages + read:packages. Save as
# KAMAL_REGISTRY_PASSWORD.

# Fill secrets
cd apps/api
cp .kamal/secrets.example .kamal/secrets
# Edit values. The template inline-comments where each comes from.

# Edit config/deploy.yml — replace <REPLACE_WITH_HETZNER_IP> twice
# with the IP from above.

# First deploy
gem install kamal
kamal setup        # installs Docker on box, pulls image, kamal-proxy
kamal env push     # uploads .kamal/secrets
kamal deploy       # full deploy, runs db:prepare via pre-deploy hook
kamal smoke        # alias for the production smoke task
curl https://api.bite-worthy.com/up
```

Subsequent deploys: `kamal deploy`. CI automation is a small follow-up after this manual flow proves out (queued as Phase 5.1.1-wiring).

### 2. Wire production email (Phase 5.2)

**Unlocks:** Devise password reset, restaurant claim verification (Phase 4.9), waitlist confirmation emails (Phase 5.10).

- Sign up for Postmark (https://postmarkapp.com).
- Verify the `bite-worthy.com` sender domain (DKIM + Return-Path DNS records).
- Generate a Server API token.
- `fly secrets set` — wait, no, that's the old wording. **Add to `.kamal/secrets`** and re-run `kamal env push`:
  ```
  SMTP_USERNAME=<postmark-token>
  SMTP_PASSWORD=<same-postmark-token>
  ```
  (Postmark uses the same token for both fields.)
- Confirm: `kamal smoke` continues to pass; then `bin/rails biteworthy:email:smoke EMAIL=you@example.com` over `kamal app exec` to send a test message.

### 3. Wire production storage (Phase 5.3)

**Unlocks:** review photos + dish photos persisting across deploys.

- Cloudflare → R2 → create bucket `biteworthy-blobs`.
- Generate an R2 API token with Object Read + Write on that bucket.
- Add to `.kamal/secrets`:
  ```
  R2_ACCESS_KEY_ID=<token-id>
  R2_SECRET_ACCESS_KEY=<token-secret>
  R2_BUCKET=biteworthy-blobs
  R2_ENDPOINT=https://<accountid>.r2.cloudflarestorage.com
  ```
- `kamal env push && kamal deploy`.
- (Optional) If any pre-existing blobs exist on `:local`, run `kamal app exec "bin/rails biteworthy:storage:backfill EXIT_CODE=1"` to migrate them to R2.

### 4. Provision the web app on Vercel (Phase 5.4)

**Unlocks:** `bite-worthy.com` resolving to the marketing landing + the SSR restaurant pages.

- Sign up for Vercel (Hobby tier free).
- Import the GitHub repo via the Vercel dashboard. Vercel auto-detects `apps/web`.
- Set environment variables in Vercel project settings:
  - `NEXT_PUBLIC_API_BASE=https://api.bite-worthy.com`
  - `NEXT_PUBLIC_COOKIE_DOMAIN=.bite-worthy.com`
  - `NEXT_PUBLIC_SITE_URL=https://bite-worthy.com`
- Add `bite-worthy.com` + `www.bite-worthy.com` as custom domains. Vercel emits the DNS records.
- Push to master triggers an auto-deploy.

### 5. Cassette recording for live AI ingestion (Phase 4.11.0 / 4.11.2-cassette)

**Unlocks:** the integration smoke test for `ExtractMenuJob` flips from `skip` to a real replay; gives end-to-end confidence the prompt + schema work against a real restaurant menu.

- Confirm Anthropic billing tier covers the recording (~$0.05 per menu).
- Local: from `apps/api/`, run the cassette-recording mode:
  ```bash
  ANTHROPIC_API_KEY=<key> bin/rspec spec/jobs/extract_menu_job_spec.rb
  ```
  with VCR `record: :once` against `apps/api/spec/fixtures/menus/sample.jpg` (the committed Simply Tasty Thai page).
- Commit the recorded cassette under `apps/api/spec/cassettes/`.
- Replace the `skip` block in `extract_menu_job_spec.rb` with the `VCR.use_cassette` invocation.
- The loop's next tick will attempt this automatically after Anthropic cap reset (~49 min from this writing); if you'd rather drive it manually, do it now.

### 6. Seed 30 Durango restaurants (Phase 5.7)

**Unlocks:** real restaurants on `bite-worthy.com` and `/durango/[diet]`. Required for the launch demo.

- Research + populate `docs/seeds/durango.csv` (gitignored). Columns documented in `docs/seeds/durango.csv.example`. Find each restaurant's menu URL (PDF or web) — independent restaurants only, no chains.
- Confirm Anthropic billing tier covers ~$15 (~$0.50 × 30).
- Run from a `kamal app exec` on the production box:
  ```
  bin/rails biteworthy:seed:durango FILE=docs/seeds/durango.csv
  ```
- Use the swipe-verify queue (mobile or `/admin`) to accept items per restaurant. The 80%-accepted threshold flips each run + restaurant to `:published`.

### 7. PostHog analytics (Phase 5.8-wiring)

**Unlocks:** funnel measurement (`app_open` → `profile_set` → `menu_filtered` → `restaurant_tap`).

- Sign up for PostHog Cloud, create a "BiteWorthy" project, generate a project API key.
- Vercel: set `NEXT_PUBLIC_POSTHOG_KEY=<key>`.
- EAS: set `EXPO_PUBLIC_POSTHOG_KEY=<key>` in the project's env.
- Open follow-up PR `claude/phase-5.8-wiring`:
  - `pnpm add posthog-js -F @biteworthy/web`
  - `pnpm add posthog-react-native -F @biteworthy/mobile`
  - Wrap each SDK in an `AnalyticsClient` adapter; inject into `buildWebTracker` / `buildMobileTracker`.
  - Instrument the 9 events at their call sites per `docs/analytics.md`.

### 8. App Store + Play Store submission (Phase 5.9-wiring)

**Unlocks:** the app on phones.

- Sign up for Apple Developer Program ($99/yr) + Google Play Console ($25 one-time).
- **Lawyer reviews + signs off on `/privacy` + `/terms`.** Both pages currently render with a DRAFT banner; remove the banner once approved.
- Replace `apps/mobile/eas.json` placeholders (`REPLACE_WITH_APPLE_ID@bite-worthy.com`, `REPLACE_WITH_ASC_APP_ID`, `REPLACE_WITH_TEAM_ID`) with real values.
- Commit `play-service-account.json` (gitignored) for Google Play submit.
- Generate binary assets — see `apps/mobile/assets/README.md` for sizes + the `sharp` render pipeline. The SVG source needs to be designed first.
- Wire expo-router `/screenshots/[id]` test routes that drive each marketing screenshot deterministically against the Phase 5.7 seeded restaurants.
- `eas build --profile production --platform all` then `eas submit --profile production --platform all`. Apple review 1–7 days; Google Play Internal track typically minutes.

### 9. Press outreach (Phase 5.10)

**Unlocks:** humans hearing about the app.

- Customize the templates in `docs/outreach/` with current editor names, your phone, embargo date.
- Send 7 days before public launch. Follow up after 3 days (5 for KSUT).
- Day-of: stage the `launch-day.md` social posts.

## CI status

- `ci-api.yml` — runs on every PR touching `apps/api/`. Postgres 16, ImageMagick installed, full rspec, Brakeman + Rubocop informational.
- `ci-js.yml` — runs on `apps/web/` / `apps/mobile/` / `packages/` / root config. typecheck → lint → test.
- `pr-title.yml` — enforces lowercase-after-colon conventional-commit titles (informational).
- `auto-merge.yml` — squash-merges PRs labeled `claude-cd` + `auto-merge-ok` once branch protection allows.

## Known gaps + Discovered followups

- **jest-expo + web `@testing-library/react` wiring** — single Discovered note covers both apps. Once landed, retroactively add UI snapshots from Phases 3.2 / 3.3 / 3.4 / 3.5 / 4.11.4.
- **Auto-merge race** — twice now (#150, #172) a follow-on commit has been lost when auto-merge enabled before the second push. Either tighten the loop's flow (push everything in one go) or gate auto-merge on a manual `ready-to-merge` label after final push.
- **Restaurant `neighborhood` column** — Phase 5.6 surfaced this; the SEO page wanted to show neighborhood names but the addresses table doesn't have that column. Worth a Phase 6+ followup once the launch market grows beyond Durango itself.

## Stop conditions tripped

Per delivery-playbook.md §7, the loop pauses when every Next-up item is `[BLOCKED]` or implicitly gated on human action. This is that state.

The next loop tick (post-Anthropic-cap-reset at 2026-05-01 00:00 UTC) will attempt the cassette retry. Beyond that, the loop has no further code to ship until either:
- A wiring PR's prerequisite credential lands (PostHog key, Apple/Google account, Vercel/Hetzner provisioning), OR
- A human promotes a Discovered followup into Next-up, OR
- A new phase is drafted (Phase 6+).
