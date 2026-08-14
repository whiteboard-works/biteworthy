# Launch & Growth Plan

> Consolidated, dependency-ordered execution plan for taking Biteworthy from
> "code-complete, credential-gated" to launched — plus the loop-shippable growth
> work (lower-the-gate + restaurant QR) that can run in parallel.
>
> **Created:** 2026-06-30 · Derived from `docs/launch-readiness.md`,
> `docs/roadmap.md`, `docs/strategy-2026-h2.md`, the ADRs, and a code
> investigation of `apps/web` / `apps/api` / `apps/mobile`. When this doc and the
> live tracking docs disagree, the tracking docs win — reconcile, don't fork.

## The one structural insight

There are **two independent tracks**, and they have been mistaken for one — which
is why the project stalled at "feature-complete" with nothing public shipped.

- **Track A — Launch (all human-gated).** Provisioning, payments, a lawyer, DNS,
  a real-device test. The autonomous delivery loop *cannot touch any of it*. This
  is the real blocker.
- **Track B — Lower-the-gate + QR (all loop-shippable code).** Friction removal,
  SEO/visibility, and the restaurant QR program. The loop is allowed to build
  every bit of this **today, in parallel**, while the human works Track A.

They converge at launch. The move: **you take Track A; the loop takes Track B.**

---

## The three keystones (start these first)

1. **First `kamal deploy`** — unblocks email, storage, web, seed, screenshots,
   press. Nothing public exists until this runs.
2. **L1 attorney sign-off** (Privacy + ToS) — long lead time (external party);
   blocks DRAFT-banner removal *and* mobile store submission. Start day one even
   though it finishes late.
3. **Anthropic billing** — cheap, but unblocks both the AI cassette and the
   30-restaurant seed.

---

# Track A — Launch sequence (all manual)

Everything below requires **you, by hand**. Grouped into waves; within a wave,
items run in parallel. HARD = legally/technically blocks public launch; SOFT =
can launch without, or fast-follow.

### Wave 0 — today, no prerequisites (all parallel)

| Item | Cost | Gate |
|---|---|---|
| Create **Hetzner** account + API token + ed25519 SSH key | ~$9/mo all-in | HARD |
| Create **Neon** `biteworthy-prod` (aws-us-east-1), copy pooled URL | free tier | HARD |
| Create **GHCR PAT** (`write:packages` + `read:packages`) | free | HARD |
| **Start L1** — engage Colorado attorney for Privacy + ToS ⏳ *long lead* | varies | HARD |
| Register **DMCA designated agent (L2)** + repeat-infringer process | ~$6 | HARD (DMCA feature) |
| Sign up **Resend / Cloudflare R2 / Vercel / PostHog** accounts | free tiers | mixed |
| **Apple Developer** ($99/yr) + **Google Play Console** ($25 one-time) | $124 | HARD (mobile) |
| Turn on **Anthropic billing** | ~$15 total downstream | keystone |
| Design **`icon-source.svg`** | — | HARD (mobile) |
| L4 — trademark knockout search + `LICENSE` decision | — | SOFT |

### Wave 1 — needs a box / keys to exist

- [ ] **Point DNS `api.bite-worthy.com` A-record → Hetzner IP**
- [ ] **Record the AI cassette** — replace the `skip` block in
      `apps/api/spec/jobs/extract_menu_job_spec.rb` with `VCR.use_cassette`
      (`record: :once` against `spec/fixtures/menus/sample.jpg`, commit it). ~$0.05.
      This is also the *first end-to-end proof the ingestion moat works against a
      real menu.* SOFT (test confidence), but do not skip it.

### Wave 2 — the keystone deploy

- [x] **Run the first `kamal deploy`** — **DONE.** API live at
      `https://api.bite-worthy.com`; subsequent deploys are automatic via
      `deploy-api.yml` on merges touching `apps/api/**`.

### Wave 3 — needs the API live

- [x] **Wire Resend** — **DONE 2026-08-14.** `mail.bite-worthy.com` verified,
      API key in `.kamal/secrets` as `SMTP_PASSWORD`, deployed and synced to
      `KAMAL_SECRETS_B64`. `biteworthy:email:smoke` delivered end-to-end and
      landed in the **inbox, not spam** — so DKIM/SPF are good enough for a
      cold sending domain. Password reset, claim verification and the waitlist
      mailer are live.
- [x] **Create R2 bucket `biteworthy-blobs` + API token.** — **DONE.** Review + dish
      photos persist across deploys. (~$1–3/mo.)
- [x] **Connect Vercel** (Hobby, free) — **DONE.** `bite-worthy.com` + `www` live,
      auto-deploying on master merge.

### Wave 4 — needs API + Vercel live

- [ ] **Seed 30 Durango restaurants** — populate `docs/seeds/durango.csv`, run
      `bin/rails biteworthy:seed:durango` via `kamal app exec --roles web` (bare
      `app exec` runs on the worker too and the two runs race — this exact
      command did it once already), swipe-verify to the
      80%-published threshold. ~$15. **HARD — coverage *is* the day-one product.**
- [ ] **Set PostHog keys** — `NEXT_PUBLIC_POSTHOG_KEY` (Vercel) +
      `EXPO_PUBLIC_POSTHOG_KEY` (EAS); verify `app_open` fires. SOFT.
- [ ] **Remove DRAFT banners** from `apps/web/src/app/privacy/page.tsx` +
      `terms/page.tsx` (+ source DRAFT comments) — **only after L1 sign-off.**
- [x] *(loop-shippable)* Phase 5.1.1-wiring — **DONE.** `deploy-api.yml` runs
      `kamal deploy` on merges touching `apps/api/**`, including auto-merged PRs
      (that needs `AUTOMERGE_TOKEN`, not `GITHUB_TOKEN`, or the merge commit
      triggers nothing).

### Wave 5 — needs seeded data + icon + L1

- [ ] **Render binary assets + wire `/screenshots/[id]` routes** against seeded
      restaurants (`apps/mobile/assets/README.md`).
- [ ] **Fill `eas.json` placeholders** — `REPLACE_WITH_APPLE_ID@bite-worthy.com`,
      `REPLACE_WITH_ASC_APP_ID`, `REPLACE_WITH_TEAM_ID`; commit the gitignored
      `play-service-account.json`.

### Wave 6 — final

- [ ] **`eas build` → `eas submit`** (Phase 5.9-wiring). Apple review 1–7 days,
      Google minutes. HARD for mobile.
- [ ] **Send press outreach** — customize `docs/outreach/` templates, send ~7 days
      pre-launch, stage `launch-day.md`. SOFT.

### Also gated on the lawyer (fast-follow, not launch-blocking for the web MVP)

- [ ] **L3** — attorney call on auto-cropping third-party dish photos
      (`dish_photo_cropper.rb` R2 rehosting). Opt-in-upload fallback exists.
- [ ] **L5** — "BiteWorthy-safe" badge (flag only, deferred).

### Dependency summary

```
Hetzner + Neon + GHCR + DNS ─┐
                             ├─► first `kamal deploy` ─► Resend / R2 / Vercel+domain
Anthropic billing ─► cassette┘                        └─► seed 30 ─► screenshots ─► eas submit
Anthropic billing ─► seed 30                                          │
L1 attorney ─► remove DRAFT banners ─► (store requires signed docs) ──┘ ─► press
Apple + Google accounts + icon.svg ─────────────────────────────────► eas submit
```

**Highest-unblock items:** (a) the first `kamal deploy`; (b) L1 lawyer sign-off;
(c) Anthropic billing.

---

# Track B — Lower the gate for usage & visibility (loop-shippable now)

The read path is **already fully anonymous**: the API skips auth on restaurant /
item reads (`apps/api/app/controllers/api/v1/items_controller.rb:19`,
`restaurants_controller.rb:24`) and already accepts `?profile=<preset>` and
`?profile_token=<token>` for filtering without an account
(`items_controller.rb:74-114`). The gate is **purely UI** — there is no logged-out
filter picker, and the SEO/share plumbing is half-wired. All of the below are code
fixes the loop can ship while the human does Track A.

### Friction — first value without an account

1. **Anonymous preset/filter picker on the restaurant page + persist to
   `localStorage`.** *(M — plumbing exists.)* **The linchpin.** It's what makes
   both the SEO funnel and the QR program deliver a *filtered* menu instead of an
   unfiltered wall. Backend (`?profile=`, `encodeProfileToken`) is done; only the
   logged-out UI is missing.
2. **Let onboarding finish without login** — store the avoid-list as a
   `profile_token` in `localStorage`, apply via `?p=` across restaurants, offer
   "save to account" *afterward*. *(M.)* Today onboarding 401s straight to
   `/login` (`apps/web/src/app/onboarding/page.tsx:144`), so building a filter
   *requires* an account. Directly attacks the strict-mode-sparsity / activation
   risk in `docs/strategy-2026-h2.md` §6.

### Visibility — so people can find it at all

3. **Populate `restaurantSlugs` (+ `/u` handles) in the sitemap.** *(S — the hook
   at `apps/web/src/lib/sitemap.ts:40` exists but is never filled.)* Today **zero
   restaurant pages are indexed** — only `/`, `/story`, `/login`, `/signup`,
   `/durango/<diet>`.
4. **Add `generateMetadata` + Restaurant/Menu JSON-LD to `/restaurants/[slug]`.**
   *(S–M — copy the `durango/[diet]/page.tsx:42-57` pattern.)* Every restaurant
   currently shares one generic `<title>`; no rich results, no social unfurls.
5. **Forward diet context from the durango cards** — link
   `/restaurants/<slug>?profile=<diet>` instead of bare `/restaurants/<slug>`
   (`apps/web/src/app/durango/[diet]/page.tsx:180`). *(S — backend already accepts
   `?profile=`.)* Today an SEO click from "Celiac restaurants in Durango" lands on
   an **unfiltered** menu, dropping the whole point.
6. **Write strictness + active filter into the URL** so every filtered view is
   bookmarkable / shareable / crawlable, not just the clipboard token
   (`RestaurantClient.tsx` strictness is React-state-only today). *(S.)*
7. **`generateMetadata` + OG for `/u/[handle]`** (review count, recent reviews) so
   shared reviewer cards unfurl. *(S — page is already SSR.)*
8. **OG unfurl for `/r/<slug>?p=` share links** ("N safe dishes at <name>"),
   building on #4. *(M.)*

**Highest leverage:** #1 (anonymous picker) + #3/#5 (index + don't drop the
filter). Small, exploit existing public endpoints, and they're the difference
between "we shipped a page" and "the page is useful and findable."

---

# Track B (cont.) — Restaurant QR program

**Verdict: ~80% already built.** A restaurant QR that goes scan → instant filtered
menu → (optionally) into the app is mostly a config + image-generation job, not a
new feature.

### What already exists

- **Stable public URL per restaurant:** `slug` on the model
  (`apps/api/app/models/restaurant.rb:15`), and `/r/<slug>` re-exports the SSR
  restaurant page (`apps/web/src/app/r/[slug]/page.tsx`). The fetch is explicitly
  anonymous. **This is what the QR should encode.**
- **No-login filtering** via `?p=<token>` on that page, plus a strictness toggle.
- A custom scheme (`biteworthy`, `apps/mobile/app.json:5`) and a mobile restaurant
  screen (`apps/mobile/app/restaurants/[id].tsx`).
- The claim flow already composes per-restaurant URLs
  (`restaurant_claims_controller.rb:64`) — a natural place to hand owners their QR.

### Phase 1 — web-only (ships now, effort S)

Add QR generation (e.g. the `rqrcode` gem) that encodes
`https://<host>/r/<slug>`, exposed as a web-admin action or a download endpoint.
That alone delivers "table-tent → scan → filtered web menu, no install."

- **Depends on:** the restaurant being `status: "published"`
  (`restaurants_controller.rb:53` 404s otherwise) → needs Track A deploy + seed.
- **Best paired with** Track B lever #1 (anonymous picker) so the scanning diner
  can actually pick their diet.

### Phase 2 — deep-link into the app (effort M)

- Add `ios.associatedDomains: ["applinks:<host>"]` + `android.intentFilters` for
  `/r/*` and `/restaurants/*` to `apps/mobile/app.json`.
- Ship `apple-app-site-association` + `.well-known/assetlinks.json` from
  `apps/web/public` (+ `next.config.ts` headers for correct content-type).
- Add the expo-router linking map so `/r/<slug>` resolves to `restaurants/[id]`
  (server-side `find_by_id_or_slug!` handles slug-vs-UUID).
- **None of this exists today** (no AASA, no assetlinks, no `associatedDomains`).
- **Blocked on:** the **Apple Team ID + Android release signing SHA-256**, which
  come from the Apple/Google accounts in Track A Wave 0 — the one piece of Track B
  that waits on Track A.

### Why it matters

The QR is a direct answer to the **frequency / cold-start** risk in
`docs/strategy-2026-h2.md`: a restaurant displaying "see what *you* can eat here"
is owner-independent distribution that creates coverage and pulls users online
without an app install — the HappyCow-style loop the strategy is betting on.

---

## Outstanding manual items (Track A checklist)

- [x] **Hetzner + Neon + GHCR provisioning** → **first `kamal deploy`** (keystone #1) — done; API live, and merges touching `apps/api/**` now deploy themselves
- [ ] **Engage attorney for L1 Privacy/ToS sign-off** (keystone #2 — start now, long lead)
- [ ] **Enable Anthropic billing** (keystone #3)
- [ ] **Apple Developer ($99) + Google Play ($25) + DMCA agent ($6)**
- [ ] ~~Resend~~ · ~~R2~~ · ~~Vercel + domain~~ (all done) · **PostHog** key wiring
- [ ] **Design `icon-source.svg`**
- [ ] **Seed 30 Durango restaurants**
- [ ] **Remove DRAFT banners** (post-L1)
- [ ] **For QR Phase 2:** capture the **Apple Team ID + Android signing SHA-256**
      when setting up the store accounts

## Recommended first loop PR (Track B)

Lead with the slice that makes everything else deliver value:
**anonymous filter picker (#1)** + **sitemap / metadata / don't-drop-the-filter
(#3, #4, #5)** + **QR Phase 1**. These are the keystone of Track B; the rest of the
visibility work stacks on top.
