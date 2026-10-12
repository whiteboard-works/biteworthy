# Launch readiness — the human checklist

What only a person can do between the product as it runs today and the
app in the stores, in dependency order, with the commands. Each step says
what it unlocks and whether it is done. The roadmap's *Launch* section is
the short list; this is the run book behind it, and it is kept current.
What has shipped stays here as the run book for a rebuild or a rotation.

Where things stand on 2026-10-12: the API, email, storage, the web app,
analytics, the ingestion cassette, and the Durango seed are done and
live. Open: the L1 attorney review, the DMCA agent, the store accounts
and submission, database snapshots, the error-reports repo, and press.

## What you (the human) need to do

Numbered roughly in dependency order. Each step lists what it unlocks.

### 1. Provision the Rails API — ✅ **DONE**

**Unlocks:** every API-dependent flow. All live: `https://api.bite-worthy.com/up` returns 200 and merges touching `apps/api/**` deploy themselves.

Kept as the runbook for rebuilding the box:

```bash
# Hetzner
hcloud server create --name biteworthy-api --type cpx21 \
    --image ubuntu-24.04 --datacenter ash-dc1 --ssh-key skylar
# Note the IP. DNS: api.bite-worthy.com A → that IP.

# Neon: sign up at neon.tech, create biteworthy-prod in
# aws-us-east-1, copy the POOLED connection string.

# GHCR: GitHub → Settings → Developer settings → PAT (classic)
# with write:packages + read:packages. Save as
# KAMAL_REGISTRY_PASSWORD. Laptop deploys only: deploy-api.yml
# logs in with its own GITHUB_TOKEN.

# Fill secrets
cd apps/api
cp .kamal/secrets.example .kamal/secrets
# Edit values. The template inline-comments where each comes from.

# Point everything at the new IP. There are no <REPLACE_WITH_...>
# placeholders any more -- the current IP is hardcoded in several
# places and a rebuild has to update ALL of them, or CI keeps
# deploying to the box you just replaced:
#   1. apps/api/config/deploy.yml  -- the `hosts:` entry under BOTH
#      the web and worker roles (two lines, same IP).
#   2. .github/workflows/deploy-api.yml -- the ssh config + kamal
#      host block near the end also name it literally.
#   3. DNS: api.bite-worthy.com A -> new IP.
#   4. The SSH_KNOWN_HOSTS repo secret -- re-pin to the NEW box's
#      host keys. Only ever re-pin after confirming out-of-band that
#      the box really was rebuilt; a host-key change you cannot
#      explain is what a MITM looks like.
#   5. SSH_PRIVATE_KEY, if the deploy key changed.
# KAMAL_SECRETS_B64 does not need touching -- its values are
# host-independent.

# First deploy
gem install kamal
kamal setup        # installs Docker on box, pulls image, kamal-proxy
kamal env push     # uploads .kamal/secrets
kamal deploy       # full deploy; db:prepare runs from the entrypoint on puma boot
kamal smoke        # alias for the production smoke task
curl https://api.bite-worthy.com/up
```

Subsequent deploys are automatic: `.github/workflows/deploy-api.yml` runs `kamal deploy` on every merge to master touching `apps/api/**`. Run `kamal deploy` by hand only for out-of-band ships.

### 2. Wire production email — ✅ **DONE 2026-08-14**

**Unlocks:** Devise password reset, restaurant claim verification (Phase 4.9), waitlist confirmation emails (Phase 5.10). All three are live.

Provider is **Resend** (PR #403 — the Postmark account in ADR 0003 was never
stood up, and Mailgun's free plan refused a second sending domain). The
non-secret half is committed in `deploy.yml`'s `env.clear`
(`smtp.resend.com`, port 587, username `resend`, domain
`mail.bite-worthy.com`).

`mail.bite-worthy.com` is verified, the API key is in `.kamal/secrets` as
`SMTP_PASSWORD`, deployed, and synced to `KAMAL_SECRETS_B64`.
`bin/rails biteworthy:email:smoke` delivered end-to-end and the message landed
in the **inbox rather than spam**, which is the part worth recording — a cold
sending subdomain often doesn't on the first try.

The steps below are kept as the runbook for rotating the key or standing the
provider up again on a new box:

- In Resend, add **`mail.bite-worthy.com`** as a sending domain and publish the
  DKIM + SPF records it emits at the registrar. The subdomain is deliberate —
  the From address (`no-reply@mail.bite-worthy.com`) has to live under whatever
  domain is verified.
- Generate a Resend **API key** with send access.
- **Add to `.kamal/secrets`** and re-run `kamal env push && kamal deploy`:
  ```
  SMTP_PASSWORD=<resend-api-key>
  ```
  Only the key is a secret — `SMTP_USERNAME` is the literal string `resend` and
  is already set in `env.clear`.
- **Then run `bin/kamal-secrets-push`** to sync the `KAMAL_SECRETS_B64` repo secret.
  `deploy-api.yml` rebuilds `.kamal/secrets` from it on every automated deploy, so
  skipping this means the next merge to master quietly reverts the key.
  (All three commands run from `apps/api/` — Kamal resolves `config/deploy.yml`
  relative to the working directory, and step 1 already `cd`'d there.)
- Confirm: `kamal smoke` continues to pass; then `kamal app exec --roles web 'bin/rails biteworthy:email:smoke EMAIL=you@example.com'` to send a test message (`--roles web`, or it runs on the worker too and sends twice).

### 3. Wire production storage — ✅ **DONE**

**Unlocks:** review photos + dish photos persisting across deploys. Live: the `biteworthy-blobs` bucket holds every photo and menu page. Kept as the run book for rotating the token.

- Cloudflare → R2 → create bucket `biteworthy-blobs`.
- Generate an R2 API token with Object Read + Write on that bucket.
- Add to `.kamal/secrets`:
  ```
  R2_ACCESS_KEY_ID=<token-id>
  R2_SECRET_ACCESS_KEY=<token-secret>
  R2_BUCKET=biteworthy-blobs
  R2_ENDPOINT=https://<accountid>.r2.cloudflarestorage.com
  ```
- From `apps/api/`: `kamal env push && kamal deploy`, then `bin/kamal-secrets-push`
  (see above — CI rebuilds `.kamal/secrets` from the repo secret and would revert these
  otherwise).
- (Optional) If any pre-existing blobs exist on `:local`, run `kamal app exec --roles web "bin/rails biteworthy:storage:backfill EXIT_CODE=1"` to migrate them to R2.

### 4. Provision the web app on Vercel — ✅ **DONE**

**Unlocks:** `bite-worthy.com` resolving to the marketing landing + the SSR restaurant pages. Live, auto-deploying from `master`. Kept as the run book.

- Sign up for Vercel (Hobby tier free).
- Import the GitHub repo via the Vercel dashboard. Vercel auto-detects `apps/web`.
- Set environment variables in Vercel project settings:
  - `NEXT_PUBLIC_API_BASE=https://api.bite-worthy.com`
  - `NEXT_PUBLIC_COOKIE_DOMAIN=.bite-worthy.com`
  - `NEXT_PUBLIC_SITE_URL=https://bite-worthy.com`
- The browser calls the API directly for scan uploads and the onboarding taxonomy, so every web origin that serves the app (production, and any staging or preview deployment) must be in the API's `ALLOWED_ORIGINS` (`apps/api/config/deploy.yml` env.clear); an origin missing there fails those calls with a CORS error.
- Add `bite-worthy.com` + `www.bite-worthy.com` as custom domains. Vercel emits the DNS records.
- Push to master triggers an auto-deploy.

### 5. Cassette recording for live AI ingestion — ✅ **DONE**

Recorded: `apps/api/spec/cassettes/extract_menu_job/` replays in CI. Kept as the run book for re-recording after a prompt or schema change.

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

### 6. Seed Durango restaurants — ✅ **DONE** (the seed run's fixes landed 2026-10-05 as #765)

**Unlocks:** real restaurants on `bite-worthy.com` and `/durango/[diet]`. Durango is seeded and published (the seed run's pipeline fixes landed as #765). Growth is per city now: see *Multi-city* in `roadmap.md`. Kept as the run book for the next city.

- Research + populate `docs/seeds/durango.csv` (gitignored). Columns documented in `docs/seeds/durango.csv.example`. Find each restaurant's menu URL (PDF or web) — independent restaurants only, no chains.
- Confirm Anthropic billing tier covers ~$15 (~$0.50 × 30).
- Run from a `kamal app exec` on the production box:
  ```
  bin/rails biteworthy:seed:durango FILE=docs/seeds/durango.csv
  ```
- Use the swipe-verify queue (mobile or the web `/admin/runs`) to accept items per restaurant. The 80%-accepted threshold flips each run + restaurant to `:published`.

### 7. PostHog — events, errors, and logs (ADR 0009) — ✅ **DONE** except the two items below

**Unlocks:** funnel measurement (`app_open` → `profile_set` → `menu_filtered` → `restaurant_tap`), server error tracking, and logs that outlive a deploy.

- ~~Code side~~ — **done in #218 and the ADR 0009 PR**: all three apps point at BiteWorthy's own project (id 652080). The public token is pinned in `apps/web/src/lib/posthog-config.ts` (production hosts), `apps/mobile/eas.json` (production profile), and `apps/api/config/deploy.yml` (`POSTHOG_API_KEY`, `APP_ROLE`). Nothing needs setting in Vercel or EAS.
- Remaining (human):
  - [x] ~~**Verify events arrive**~~ — verified 2026-10-10 after #855 deployed: a visit to bite-worthy.com posted to `us.i.posthog.com/e/` with the 652080 token's persistence, the project's "no events yet" banner cleared, and the activity view listed `app_open` for each page load and a `$pageview` for a client-side navigation. The page-load `$pageview` was not seen from the automated browser tab because that tab was hidden, and posthog-js holds the first page view until the tab is visible (`document.visibilityState`), so it was the one event still to confirm from a normal visit; confirmed 2026-10-11 00:53 UTC through the PostHog MCP: a `$pageview` on a fresh session with `app_open` 8 ms behind it and nothing earlier in that session, which is a page load.
  - [x] ~~**Verify the API logs arrive**~~ — verified 2026-10-10: PostHog → Logs showed `service.name = Biteworthy`, environment `production`, within minutes of the API deploy.
  - [x] ~~**Verify the API reports exceptions**~~ — verified 2026-10-11 02:08 UTC: `Rails.error.report(RuntimeError.new("posthog smoke"), handled: true, context: { component: "smoke" })` from `kamal console` (run from `apps/api`) showed up as a `RuntimeError` issue under Error tracking within the minute, and the same report queued `ErrorReports::FileIssueJob` (ADR 0008).
  - [x] ~~**Remove the `NEXT_PUBLIC_POSTHOG_KEY` set in Vercel**~~ — removed by the owner 2026-10-10. Until then it was ignored on production but sent every preview deploy's traffic to the old shared project; a preview built after the removal sends nothing unless the variable is set again on purpose.
  - [ ] **Delete or redeploy the preview deployments built before that removal.** Next inlines `NEXT_PUBLIC_*` into the client bundle at build time, so a preview URL built while the variable existed still reports to the old shared project for as long as it stays reachable (Vercel → Deployments, filter to previews older than 2026-10-10).
  - [x] ~~**Re-authorize the PostHog MCP server**~~ — re-authorized by the owner 2026-10-11; `project-get` returns project 652080 and queries run. It confirmed the exception smoke above.
  - [ ] **L1 review:** `/privacy`'s PostHog entry now says it also receives error reports and logs from our servers.

### 8. App Store + Play Store submission

**Unlocks:** the app on phones.

- Sign up for Apple Developer Program ($99/yr) + Google Play Console ($25 one-time).
- **Lawyer reviews + signs off on `/privacy` + `/terms`.** Both DRAFT banners came off at the owner's call ahead of that review (`/privacy` 2026-10-05, `/terms` 2026-10-06); the review itself is still open.
- Replace `apps/mobile/eas.json` placeholders (`REPLACE_WITH_APPLE_ID@bite-worthy.com`, `REPLACE_WITH_ASC_APP_ID`, `REPLACE_WITH_TEAM_ID`) with real values.
- Commit `play-service-account.json` (gitignored) for Google Play submit.
- Generate binary assets — see `apps/mobile/assets/README.md` for sizes + the `sharp` render pipeline. The SVG source needs to be designed first.
- Wire expo-router `/screenshots/[id]` test routes that drive each marketing screenshot deterministically against the Phase 5.7 seeded restaurants.
- `eas build --profile production --platform all` then `eas submit --profile production --platform all`. Apple review 1–7 days; Google Play Internal track typically minutes.

### 9. Press outreach

**Unlocks:** humans hearing about the app.

- Customize the templates in `docs/outreach/` with current editor names, your phone, embargo date.
- Send 7 days before public launch. Follow up after 3 days (5 for KSUT).
- Day-of: stage the `launch-day.md` social posts.

### 10. Backfill gluten rows on dishes promoted before the gluten rules — ✅ **DONE 2026-10-06**

- [x] Apply run (owner, 2026-10-06).
- [x] Every dish on that run's "review by hand" list checked in admin (owner, 2026-10-06).

**Unlocks:** Celiac users stop seeing old samosas, katsu, breaded or gravied dishes, soy-sauce stir fries, and similar as safe.

Dishes promoted before #638, #766, or #794 lack the gluten rows those rules add. Run the dry run, read the list, then apply:

- `kamal app exec --reuse --roles web "bin/rails biteworthy:menus:backfill_implied_bases"`
- `kamal app exec --reuse --roles web "bin/rails biteworthy:menus:backfill_implied_bases" --env APPLY:1`

Add-only and idempotent. It never writes over what may be a person's decision: a dish missing a base that a rule live at its promotion should have added, or a dish edited since a rule went live, is listed under "to review by hand" with its admin restaurant link instead. Any FAILED line is a dish to fix by hand in admin, and the task then exits 1.

### 11. Error reports → GitHub issues (private repo + token)

`apps/api/config/deploy.yml` carries neither `GITHUB_ERROR_REPORTS_TOKEN` nor `GITHUB_ERROR_REPORTS_REPO` as of 2026-10-12, so this is open.

**Unlocks:** chat and job failures filed as GitHub issues — one per distinct failure, counted, reopened when they recur — before a user writes in. Until this is done every failure is still recorded in `error_reports` (count, first and last seen) and nothing leaves the box.

The API's `Rails.error` subscriber files through `ErrorReports::GithubIssues` (ADR 0008). It needs a repo to file into and a token that can write issues there.

- [ ] **Pick a private repo.** `whiteboard-works/biteworthy` is public, and an issue carries a backtrace and a conversation id (the message is stored and posted with its values blanked) — so not there. A new `whiteboard-works/biteworthy-ops` (private, issues on) is the clean choice. The reporter checks the repo is private before every hour's first write and refuses if it is not.
- [ ] **Create a fine-grained PAT** (GitHub → Settings → Developer settings → Fine-grained tokens): resource owner `whiteboard-works`, repository access limited to that one repo, permission **Issues: Read and write**, nothing else. Note the expiry.
- [ ] **Add it to the deploy, in this order.** First `GITHUB_ERROR_REPORTS_TOKEN=github_pat_…` in `apps/api/.kamal/secrets`, then `apps/api/bin/kamal-secrets-push`. Only then a PR adding `GITHUB_ERROR_REPORTS_TOKEN` under `env.secret` and `GITHUB_ERROR_REPORTS_REPO: whiteboard-works/<repo>` under `env.clear` in `apps/api/config/deploy.yml`. Kamal fails a deploy on a listed-but-missing secret, and merging an `apps/api` change deploys.
- [ ] **Check it fired.** After that deploy: `kamal console`, then `Rails.error.report(RuntimeError.new("error reports smoke"), handled: true, context: { component: "smoke" })`. An issue titled `[smoke] RuntimeError: error reports smoke` should appear within a minute, labelled `bug` and `auto-reported` (the reporter creates a label the repo lacks before its first issue, and finds an issue it lost track of by that label). Close it, and it stays closed unless reported again.

### 12. Database snapshots

**Unlocks:** recovering from a bad migration, a bad backfill, or a wipe. ADR 0007 records that nothing beyond Neon's own retention protects the data today.

- In the Neon console, confirm the project's point-in-time restore window (Free tier is short) or move to a plan with a longer one.
- Add a scheduled logical export (`pg_dump` from the box or a GitHub Action with the pooled URL) to R2 or another bucket, and test a restore once.
- Record the retention and the restore command in ADR 0007.

### 13. Check strict-mode coverage before a wider push

**Unlocks:** inviting people whose safety depends on strict mode without handing them an empty menu.

- From `kamal console`, count visible items per published restaurant for a strict profile on each preset; a restaurant with zero is one to confirm by hand (the admin "Confirm community menu" action, left to a person on purpose because it loosens what strict mode shows).
- Repeat for each new city before it goes public.
