# Phase 4 — Reviews + accounts (subplan)

Phase 3 made the dietary filter work for an anonymous browser; Phase 4 makes the app feel like a place you have an *account* at. The user comes back tomorrow and finds their saved profile, the items they already reviewed, the restaurants they've filtered. Owners claim their restaurants. Anyone can suggest a fix to a wrong ingredient.

The schema already carries most of what's needed (Phase 0 shipped `reviews`, `suggestions`, `restaurants.claimed_*` columns, and `User#is_admin`). This phase wires UX + auth around them.

**Demo at the end:** a logged-in user reviews a dish from a restaurant they filtered to; an owner claims that restaurant via domain-email verification; a contributor suggests a missing-ingredient fix and a reviewer accepts it.

## Stop conditions specific to Phase 4

- **Email delivery** — review confirmations + claim verification + password resets all need an outbound mailer. If `SMTP_*` ENV vars aren't set in the loop's environment, ship the wiring with the `:test` adapter and put the live-send check in `.env.example`. Don't ship a "send a real email" rspec without credentials.
- **Photo upload size limits** — Phase 4.3 attaches review photos via ActiveStorage. The `S3_BUCKET` deferral from Phase 2 still applies; falling back to local disk is fine for review photos in dev/test, but flag it in the PR.
- **Domain-email verification** — Phase 4.9 needs to send a verification email to (e.g.) `owner@durangosmelter.com`. Same SMTP gap as above. If unavailable, ship the verification-token generator + UI + spec, and have the rake task `bin/rails restaurants:claim:verify[token]` as a manual fallback for the demo.

## Tasks (one PR each)

### 4.1 — Real session cookies (retire JWT-pasting)

**Branch**: `claude/phase-4.1-session-cookies`

Phase 1.1 shipped JWT auth; the ingest screens, onboarding, and restaurant pages all ask the user to *paste a JWT* until "Phase 4 wires real sessions." This is that PR.

- Devise `:database_authenticatable` already issues a session cookie on web. Add `:rememberable` and configure a 30-day cookie lifetime.
- Web: switch the existing JWT-paste workflows on `/onboarding`, `/restaurants/[slug]`, `/ingest` to read the session cookie directly. The `bw_jwt` cookie helper from Phase 3.8 stays for *contributor token* (claim/reset) workflows but stops being the primary auth.
- Mobile: swap `expo-secure-store` in for the URL-param JWT pattern across the onboarding + ingest + restaurant screens. New `lib/auth.ts` exposes `getJwt()` + `setJwt()` + `clearJwt()` over `expo-secure-store`.
- API: no changes needed — JWT remains the mobile transport, cookie wraps the same JWT for web.
- The `?jwt=…` query-param shortcut stays in dev mode only, gated by `Rails.env.development?`, so the loop's automated checks can still inject a token.

**Specs**:
- Request specs that hit `GET /api/v1/profile` with a session cookie (web) and a Bearer header (mobile).
- Vitest for the cookie helpers (extend the Phase 3.8 `jwt-cookie.test.ts`).
- Mobile jest for the secure-store wrapper (mock `expo-secure-store`).

**Acceptance**: every screen the loop touches authenticates without paste-the-JWT prompts. Documented in each screen's comment block (the prior `until Phase 4` notes get removed).

### 4.2 — Persistent "never hide this dish" override

**Branch**: `claude/phase-4.2-persistent-overrides`

Phase 3.4 shipped a session-only "show anyway" override; this PR adds the persistent variant the spec deferred.

- New table `user_item_overrides (user_id, item_id, never_hide bool, created_at)`. Composite unique index on `(user_id, item_id)`.
- API: `POST /api/v1/items/:id/never_hide` + `DELETE /api/v1/items/:id/never_hide`. Items endpoint includes `overridden_by_user: bool` per item when the request is authenticated.
- Web + mobile: the existing "Show anyway" button gains a sub-action "Never hide this dish" — once tapped, the chip flips to "Always shown — undo". The `applyOverrides` helper in `@biteworthy/filter-engine` is extended (or wrapped) so persistent overrides drop into the same visible bucket as session ones.

**Specs**: model + request specs; vitest for the new helper variant; mobile + web button rendering.

### 4.3 — Review API + photo attachment

**Branch**: `claude/phase-4.3-review-api`

The `reviews` table exists (Phase 0) with rating + body; this PR adds photos + endpoints.

- Migration: `add_attachment :reviews` via ActiveStorage `has_one_attached :photo` (no schema change, just the model wiring).
- `POST /api/v1/items/:item_id/reviews` (multipart for the photo).
- `GET  /api/v1/items/:item_id/reviews` (paginated, newest first).
- `PATCH /api/v1/reviews/:id` + `DELETE /api/v1/reviews/:id` (owner-only).
- Review payload includes `photo_url` (signed URL) when present.

**Specs**: request specs for each endpoint; auth boundary (only owner can edit/delete); rating validation already in the model.

**Cross-cutting**: rswag annotations so `packages/api-types` regen picks up the new shapes (Phase 1.6 pipeline).

### 4.4 — Mobile review UX

**Branch**: `claude/phase-4.4-mobile-reviews`

- New `app/items/[id].tsx` item detail screen showing the item's name + sectioned reviews.
- "Write a review" sheet: 5-star tap, optional photo (re-uses Phase 2.6 camera capture), text body.
- The restaurant page (`app/restaurants/[id].tsx`) gains a "X reviews" badge per item that opens the detail screen.

**Specs**: jest for the API client; the screens follow the Phase 3 "no UI snapshot until jest-expo lands" pattern.

### 4.5 — Web review UX

**Branch**: `claude/phase-4.5-web-reviews`

- Mirror of 4.4 on Next.js. New `/restaurants/[slug]/items/[id]` route (server-rendered for SEO).
- "Write a review" inline form on the same page. Photo upload via the same multipart endpoint.

**Specs**: vitest for the API client; client island gets a render test once the jest-expo discovered followup is unblocked (or RTL setup lands as part of this PR — see Discovered).

### 4.6 — Review moderation queue (Avo)

**Branch**: `claude/phase-4.6-review-moderation`

- New `Avo::Resources::Review` (read-write for admins) + bulk actions: hide, mark as spam, delete.
- Add a `hidden_at` timestamp + `hidden_reason` enum (`spam | abuse | duplicate | off_topic`) to reviews. Hidden reviews don't appear in the public API responses.
- Avo dashboard surface: "Reviews awaiting moderation" tab — the queue grows when a review's body trips a simple keyword heuristic (TBD list, start tiny: profanity wordlist + URL detection). Reviewers can clear the queue with one click.

**Specs**: model spec for the hidden-from-public-feed scope; Avo action specs.

### 4.7 — User profile pages

**Branch**: `claude/phase-4.7-user-profile-pages`

- Public read-only `/u/:handle` page on web (server-rendered) showing display_name, member-since, recent reviews, total restaurants filtered.
- Mobile mirror: `app/users/[handle].tsx`.
- API: `GET /api/v1/users/:handle` returns the public summary (no email, no profile, no overrides).

**Specs**: request spec for the public payload (sensitive fields absent); web vitest for the page.

### 4.8 — "My filtered menus" history

**Branch**: `claude/phase-4.8-history`

- New table `restaurant_visits (user_id, restaurant_id, viewed_at)` with a unique index per `(user_id, restaurant_id, viewed_at::date)` (one row per day per restaurant per user; cheap to summarize).
- The items endpoint inserts a row when authenticated (best-effort, async via Solid Queue — never blocks the response).
- API: `GET /api/v1/profile/history` returns the most-recent N visits + a count of items shown vs hidden during that visit.
- Web + mobile: a "History" tab on the user profile + the home screen.

**Specs**: job spec for the visit-recording side effect; controller spec for the history endpoint.

### 4.9 — Restaurant claim flow (domain-email verification)

**Branch**: `claude/phase-4.9-restaurant-claim`

- Web: a "Claim this restaurant" button on `/restaurants/[slug]` (visible only when `restaurant.claimed_by_user_id` is null). Opens a form: enter `@<domain>` email, receive a one-time link.
- The link routes back to `/restaurants/[slug]/claim?t=<token>`; clicking confirms `claimed_at` + `claimed_by_user_id` on the restaurant.
- The token table reuses `suggestions` with `kind: 'claim'` + `payload: {email, token, expires_at}` to avoid a new schema. `Suggestion#accept!` does the claim transition.
- Domain match heuristic: token email's domain must match the restaurant's `website` host (or `www.` prefix removed). Mismatch = manual admin review (Avo highlights these).

**Specs**: token expiry, domain-match logic, accept-via-Suggestion idempotence.

### 4.10 — Suggestion queue UX (community edits)

**Branch**: `claude/phase-4.10-suggestion-ux`

- A "Suggest a fix" link on every item: launches a tiny form for "wrong ingredient", "missing tag", "rename", etc. Maps to `Suggestion.create(kind:, payload:, subject: item)`.
- Owner of a claimed restaurant sees their suggestions queue at `/restaurants/[slug]/suggestions` (web) or a deeplink in mobile. One-tap accept/reject.
- Accepting a `kind: add_ingredient` suggestion materializes an `ItemIngredient` join row (mirrors `IngestionItem#promote!`).

**Specs**: request specs for create + accept; per-kind acceptance behavior.

## Cross-cutting

- **Telemetry hooks (PostHog)**: every Phase-4 surface emits the relevant `track(...)` placeholder events that Phase 5 wires for real (`review_posted`, `restaurant_claimed`, `suggestion_submitted`, `history_opened`). Same pattern Phase 3 used.
- **OpenAPI codegen**: each PR with a new endpoint runs `pnpm --filter @biteworthy/api-types build:codegen` and commits the regenerated `packages/api-types/src/generated.ts`. CI's `codegen:check` keeps the spec in sync with the rswag annotations.
- **JWT paste removal**: every Phase 4.X PR that touches a screen with a `until Phase 4` comment from earlier phases must remove that comment as part of the diff. Phase 4.1 lands the auth wiring; subsequent PRs delete the workaround text.
- **Mobile UI snapshots**: the jest-expo Discovered followup blocks UI-snapshot coverage for everything we ship in Phase 4. If the loop has cycles to spare between feature PRs, take that followup as a standalone PR — it'll let 4.4 / 4.5 / 4.7 ship snapshots in the same PR.

## Out of scope for Phase 4

- Restaurant photo galleries (Phase 5 if at all — rich media tends to get its own redesign cycle).
- Reply threads on reviews (defer; 1-deep is enough for v1).
- Push notifications for moderation / claims (Phase 5).
- Automatic spam ML — Phase 4.6 ships a hand-rolled keyword heuristic; ML is a separate decision.
- Social graph (follows, friends-feed). Explicitly out of v1 per `docs/roadmap.md`.
