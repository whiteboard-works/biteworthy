# Legal remediation plan

Derived from the pre-launch legal risk memo (2026-06-14). Sequenced so the
two things fully in our control with no external dependency — the **Privacy
Policy** and **Terms of Service** copy — go first, then the engineering work,
then the items that genuinely need a licensed Colorado attorney or an external
registration.

**Owner tags:** `[ENG]` we build it · `[COPY]` text-only edit to a legal page ·
`[DECISION]` needs a founder call before the text can be written ·
`[ATTORNEY]` needs a licensed lawyer · `[OPS]` an external registration/process.

**Source files for Phase 1:**

- `apps/web/src/app/privacy/page.tsx`
- `apps/web/src/app/terms/page.tsx`

---

## Decisions that gate the Phase 1 copy

**Answered 2026-06-14:** (1) arbitration + class-waiver **included, 30-day
opt-out**; (2) **US-only** at launch (CCPA now, GDPR stubbed); (3) minimum age
**13+**; (4) analytics **opt-in + strip dietary fields** to be built (E7), Phase
1 writes honest interim wording; (5) keep the **manual** email-driven
deletion/export promise, drop the `removed_user` technical claim.

These change the words we put on the page, so they're answered before (or
alongside) Phase 1. Defaults in **bold** are my recommendation.

1. **Arbitration + class-action waiver in the ToS?** `[DECISION]`
   For a product with mass-tort-shaped downside (many similarly-situated
   allergic users), a mandatory-arbitration + class-waiver clause with a 30-day
   opt-out is the standard structural defense. Downsides: per-claim arbitration
   fees, some user goodwill cost. **Recommend: include it, with opt-out.**
2. **Launch audience: US-only, or EU/UK too?** `[DECISION]`
   The store listings say US-only at launch. If true, Phase 1 writes
   CCPA/CPRA-style state-privacy rights now and defers full GDPR
   (lawful-basis, data-controller, EU representative, 16-yr threshold) to when
   we go international. **Recommend: US-only now; GDPR section stubbed + queued.**
3. **Minimum age: 13 or 16?** `[DECISION]`
   Current policy says "for adults" but enforces against under-13 (COPPA). With
   no age gate today (Phase 2 builds one), the policy should state a real
   minimum. **Recommend: 16+ to create an account** (clears COPPA cleanly and
   most of GDPR Art. 8), stated in both pages.
4. **Interim deletion/export: commit to manual fulfillment now?** `[DECISION]`
   The policy already promises email-driven export + deletion "within 30 days."
   A human can honor that manually until Phase 2 ships the endpoints. **Recommend:
   yes — keep the promise, assign the inbox, drop the specific `removed_user`
   technical claim** (reword to "we delete or anonymize your reviews").
5. **Web analytics direction.** `[DECISION]`
   Today web analytics default to **opt-out** (on) and send `strictness` +
   dietary-preset slugs + avoid/hidden counts tied to an identified user — which
   contradicts the policy's "anonymous / opt-in" wording. Two honest paths:
   (a) reword the policy to match today's behavior, or (b) flip web to opt-in +
   strip dietary fields (Phase 2) and keep the cleaner wording. **Recommend: (b)
   — do the engineering, keep the strong privacy promise.** Phase 1 writes the
   interim-honest wording until (b) lands.

---

## Phase 1 — Privacy & ToS copy (do first) `[COPY]`

All edits land in the two page files above. Bump `LAST_UPDATED` on both. Keep
the `DraftBanner` until an attorney signs off (Phase 3).

### 1A — Privacy Policy

- [x] **P1. Fix stale infra facts.** "Where data lives" still says _Postgres on
      Fly.io (Denver)_. We moved to **Neon Postgres (AWS us-east-1)** + **Hetzner
      compute (Ashburn, US)** per ADR 0007 (#182, Fly.io retired). Correct the
      hosting list; keep R2 / Anthropic / Postmark / PostHog.
- [x] **P2. Add a "Data retention" section.** State how long we keep profile,
      reviews, and `restaurant_visits`, and the deletion timeline. (Memo Issue 3.)
- [x] **P3. Add a "Your privacy rights" (CCPA/CPRA) section.** Right to know /
      delete / correct, the explicit "**We do not sell or share your personal
      information**" magic words, and no-discrimination. (Memo Issue 6.) Stub a
      GDPR subsection per Decision 2.
- [x] **P4. Disclose that reviews are public.** Note handle + review text/photo
      are public and can reveal preferences. (Memo Issue 6 — de-anonymization.)
- [x] **P5. Reconcile the Children section** to the Decision-3 minimum age;
      align the COPPA/GDPR threshold wording.
- [x] **P6. Make the analytics wording honest** (Decision 5). Until Phase 2's
      opt-in/strip ships: state web analytics are on-by-default with an opt-out +
      DNT, and disclose the coarse dietary signals sent (strictness, preset, counts).
- [x] **P7. Make the deletion/export wording honest** (Decision 4). Keep the
      manual email process; drop the specific `removed_user` claim.
- [x] **P8. Tighten the Contact section** (fix the sentence fragment; point
      takedowns at the DMCA contact added in 1B/T6).
- [x] **P9. Disclose waitlist email collection** (matrix row 14) — the landing
      waitlist form stores emails; added to "What we collect".
- [x] **P10. Disclose shareable-filter-link data** (matrix row 13) — `?p=` links
      carry avoid-lists + strictness; added to "What's public".
- [x] **P11. Retention = account lifetime + 12-month purge** after deletion
      (matrix row 12; founder decision 2026-06-14), not a fixed clock.

### 1B — Terms of Service

- [x] **T1. Add "Disclaimer of warranties (AS IS)."** `[ATTORNEY]` to finalize;
      Phase 1 lands solid draft language.
- [x] **T2. Add "Limitation of liability"** (exclude consequential damages, cap
      liability). `[ATTORNEY]` to finalize.
- [x] **T3. Add "Indemnification"** — users indemnify for their uploads and any
      URL they submit to the ingestion fetcher. `[ATTORNEY]` to finalize.
- [x] **T4. Add "Dispute resolution: arbitration + class-action waiver"** with a
      30-day opt-out, per Decision 1. `[ATTORNEY]` to finalize.
- [x] **T5. Strengthen the allergen disclaimer** to name the false-negative case
      explicitly ("we may fail to flag an allergen the menu didn't spell out") and
      to say the disclaimer is also shown in the app (true once Phase 2 ships the
      in-app banner). (Memo Issue 1.)
- [x] **T6. Add "Copyright & DMCA"** — designated-agent contact, notice +
      counter-notice procedure, repeat-infringer policy. (Memo Issue 4; text now,
      agent registration is Phase 3 / OPS.)
- [x] **T7. Extend Acceptable use** to cover the URL-fetch path (user must have
      rights to content they point us at), not just uploads.
- [x] **T8. Add an "Acceptance of terms" clause** — use constitutes acceptance;
      reference the onboarding acknowledgment (live once Phase 2 ships it).

**Phase 1 acceptance:** both pages typecheck/lint/build; `pnpm --filter
@biteworthy/web test` green (the draft-banner test still passes); every promise
on the page is either backed by code today or by a committed manual process; no
stale infra facts. Ship as one PR: `docs:`/`feat(web):` per conventional-commit
rules. **Does not** remove the DRAFT banners — that waits on Phase 3.

---

## Legal ↔ code alignment matrix

The audit (verified 2026-06-14 against the working tree) of every promise the
legal pages now make, what the code actually does, and the task that closes the
gap. **Direction:** `code→legal` = build code to honor a promise · `legal→code`
= copy already adjusted to match code (done in Phase 1) · `both` = needs each.

| #   | Legal statement (page)                                                                   | Code reality (verified)                                                          | Status                 | Action                                | Direction        |
| --- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ---------------------- | ------------------------------------- | ---------------- |
| 1   | Allergen disclaimer / "best guess" (ToS)                                                 | only on `/terms`; no in-app banner, no acceptance                                | ABSENT in-app          | **E1**                                | code→legal       |
| 2   | "export … JSON archive within 30 days" (Privacy)                                         | no export endpoint; manual only                                                  | ABSENT                 | **E3** (interim: manual)              | code→legal       |
| 3   | "delete your account … within 30 days; delete or anonymize reviews" (Privacy)            | no `destroy` action; no anonymization                                            | ABSENT                 | **E2** (interim: manual)              | code→legal       |
| 4   | "update your dietary profile in the app" (Privacy)                                       | `PATCH /api/v1/profile` + onboarding flow exist                                  | EXISTS                 | —                                     | aligned          |
| 5   | review correction implied by "edit … reviews"                                            | review PATCH/DELETE API exists; **no UI**                                        | PARTIAL                | **E11**                               | code→legal       |
| 6   | "opt out … toggle in /profile/settings" + DNT (Privacy/ToS)                              | DNT + `bw_analytics_opt_out` honored in `track.ts`; **no settings UI to set it** | PARTIAL                | **E7a**                               | code→legal       |
| 7   | "mobile analytics off by default … enable in Settings → Analytics"                       | default-off enforced; **no Settings → Analytics screen**                         | PARTIAL                | **E7b**                               | code→legal       |
| 8   | analytics send "coarse signals (strictness/preset/counts) linked to account"             | matches code today                                                               | EXISTS                 | **E7c** strip → reword to "anonymous" | both             |
| 9   | "we do not sell or share"; no ad IDs (Privacy)                                           | true; no ad SDKs / data sales                                                    | EXISTS                 | keep; E7 must not undermine           | aligned          |
| 10  | "dietary profile is never shown publicly" (Privacy)                                      | public user endpoint excludes it; spec asserts exact keys                        | EXISTS (test indirect) | **E13** add explicit field assertions | hardening        |
| 11  | "you must be at least 13" (Privacy/ToS)                                                  | no age field, no gate                                                            | ABSENT                 | **E4**                                | code→legal       |
| 12  | visit history "kept for account lifetime; purged within 12 months of deletion" (Privacy) | no purge/retention job                                                           | ABSENT                 | **E5**                                | code→legal       |
| 13  | "a shared link encodes your avoid-lists and strictness … not identity/taste" (Privacy)   | token does exactly this; plaintext, no expiry                                    | EXISTS                 | copy done; **E6** harden              | both             |
| 14  | "Waitlist: we store your email" (Privacy)                                                | waitlist form + endpoint live                                                    | EXISTS                 | copy added Phase 1 (P9)               | legal→code ✓     |
| 15  | "Copyright & DMCA … we remove infringing material and terminate repeat infringers" (ToS) | no takedown intake or repeat-infringer process                                   | ABSENT                 | **E10** + **L2**                      | code→legal + ops |
| 16  | "we may hide reviews that trip the moderation heuristics" (ToS)                          | Phase 4.6 heuristics + admin queue exist                                         | EXISTS                 | —                                     | aligned          |
| 17  | "don't scrape the API at a rate that affects others" (ToS)                               | no rack-attack / throttle                                                        | ABSENT (rule only)     | **E12** (optional)                    | code→legal       |
| 18  | warranty / liability / indemnity / arbitration (ToS)                                     | draft text only; nothing to build                                                | n/a                    | **L1** attorney                       | attorney         |
| 19  | handle shown publicly (Privacy "What's public")                                          | default handle derived from email local-part                                     | leak                   | **E9**                                | code→legal       |

---

## Phase 2 — Engineering remediation (in our control) `[ENG]`

The build work that closes the `code→legal` rows above. Priority order; each is
its own PR.

- [x] **E1. Point-of-use allergen disclaimer + onboarding acknowledgment.** (#328)
      (Row 1; Memo Issue 1 — top exposure.) Persistent, non-dismissable disclaimer
      on the filtered-menu view (web `restaurants/[slug]/RestaurantClient.tsx` +
      mobile equivalent); a one-time acknowledgment at onboarding (especially when
      an allergen avoid-list or strict mode is selected), recorded with a timestamp
      on the user/profile. Then ToS can truthfully say "shown in the app" (T5
      follow-up). Single highest-leverage item.
- [x] **E2. Account deletion endpoint.** (#329) (Row 3; Memo Issue 2.) Implement
      `destroy` in `api/v1/auth/registrations_controller.rb`; route through the ORM
      (DB FKs have no `ON DELETE CASCADE`); add `dependent:` to the orphan FKs
      (`created_by_user_id`, `claimed_by_user_id`, `ingestion_runs.user_id`);
      implement the review delete/anonymize the policy describes. rswag + codegen.
- [x] **E3. Data-export endpoint.** (#330) (Row 2; Memo Issue 2.) JSON archive of the
      user's account, profile, reviews, suggestions, visits. rswag + codegen.
- [x] **E4. Age gate (13+).** (#331) (Row 11; Memo Issue 3.) Collect/confirm age at
      signup; gate account creation. Store no more than needed (a boolean
      over-13 flag or birth year — not full DOB).
- [x] **E5. Visit-history retention purge.** (#332) (Row 12; Memo Issue 3.) On account
      deletion, purge `restaurant_visits` from active stores within 30 days and a
      backstop sweep within 12 months. Recurring job; no rolling age cap while the
      account is open.
- [x] **E6. Harden share tokens.** (#333) (Row 13; Memo Issue 3.) Add an expiry to the
      `?p=` profile token (`packages/filter-engine/src/profile-token.ts` +
      `apps/api/app/services/profile_token.rb`); sign it; keep the decoded dietary
      fields out of access logs. Both implementations + the parity tests stay green.
- [x] **E7. Analytics: opt-in + strip dietary fields.** (#334) (Rows 6/7/8; Decision 5.) - **E7a** — web `/profile/settings` page with an analytics toggle that
      writes `bw_analytics_opt_out` (the read path already exists in `track.ts`). - **E7b** — mobile Settings → Analytics screen that flips `optedIn`
      (default-off already enforced in `apps/mobile/lib/track.ts`). - **E7c** — remove `strictness` / preset-slug / dietary counts from
      identified events in `packages/analytics`, then reword the privacy/ToS
      analytics copy back to the cleaner "anonymous" promise.
- [x] **E8. User-facing "report this review."** (#335) (Row 17-adjacent; Memo Issue 6.) A
      report affordance that routes into the existing moderation queue (today it's
      heuristic + admin-only). Defensive; no current legal claim depends on it.
- [x] **E9. Public-handle email leak.** (#336) (Row 19; Memo Issue 6.) Stop deriving the
      public handle from the email local-part (`user.rb` `default_handle_from_email`);
      use a neutral default.
- [x] **E10. DMCA takedown intake.** (#337) (Row 15; Memo Issue 4.) A `/dmca` page/form +
      a repeat-infringer tracking process backing the ToS § Copyright clause.
      Pairs with L2 (register the agent).
- [x] **E11. Review edit/delete UI.** (#339) (Row 5.) Wire the existing review PATCH/DELETE
      API into the web (`ReviewsClient.tsx`) and mobile (`items/[id].tsx`) screens so
      "correct your data" is true in-app, not just by email.
- [x] **E12. API rate limiting (optional).** (#340) (Row 17.) Add rack-attack throttling so
      "don't scrape the API" is enforced, not just stated. Low priority — a ToS rule
      is valid without technical enforcement; do it for abuse protection, not legal
      necessity.
- [x] **E13. Strengthen the "profile never public" test.** (#341) (Row 10.) The current
      spec asserts exact public keys (solid but indirect); add explicit assertions
      that named dietary fields (`avoid_ingredient_ids`, `strictness`, taste arrays)
      never appear in any public response. (CLAUDE.md Rule 7.)

---

## Phase 3 — Attorney / external `[ATTORNEY]` `[OPS]`

Can't be closed by code; these are the checks worth writing.

- [ ] **L1. Licensed Colorado attorney review** of the finalized Privacy + ToS,
      including the T1–T4 protective clauses. Only after this do we remove the
      DRAFT banners and the source-file DRAFT comments. (Memo Issue 5 + launch gate.)
- [ ] **L2. Register a DMCA designated agent** with the U.S. Copyright Office
      (~$6) to secure §512 safe harbor. Wire the agent contact into ToS §Copyright
      and the `/dmca` page. (Memo Issue 4.) `[OPS]`
- [ ] **L3. Attorney call on the dish-photo cropping/rehosting.**
      (`dish_photo_cropper.rb` crops third-party menu photos and rehosts on R2.)
      Honest fair-use read is weak; likely move to a restaurant-uploads/claim-based
      photo model or owner opt-in. Decision drives whether the auto-crop ships at
      launch. (Memo Issue 4.) `[ATTORNEY]` + likely follow-on `[ENG]`.
- [ ] **L4. "BiteWorthy" trademark clearance** (basic knockout search) and a
      decision on the `[OPS]` LICENSE file for the public repo. (Memo §III.)
- [ ] **L5. Defer "BiteWorthy-safe" badge** (endorsement liability) to the
      supply-side phase — flag only, no work now.

---

## Mapping back to the memo

| Memo issue                                     | Covered by                                                  |
| ---------------------------------------------- | ----------------------------------------------------------- |
| 1 — disclaimer placement                       | E1 (in-app + onboarding), T5 (ToS text)                     |
| 2 — policy promises vs code                    | P6/P7 (honest interim text), E2/E3 (build it), E11 (review) |
| 3 — health data: age/retention/URL             | P2/P11 (text), E4/E5/E6                                     |
| 4 — photo copyright + DMCA                     | T6 (text), E10 (intake), L2/L3 (register + fair-use)        |
| 5 — missing ToS protective clauses             | T1–T4 (draft text), L1 (attorney)                           |
| III — cookies/CCPA/handle/reporting/license/TM | P3/P4 (text), E7/E8/E9/E13 (build), L4                      |

**Sequence:** Phase 1 (copy) is shipped. Phase 2 items are independent PRs —
**E1 first** (top exposure), then E2/E3 (make the deletion/export promises true),
then E4–E13. Phase 3 runs in parallel and is the true launch gate. Each Phase 2
PR that closes a `code→legal` row should, in the same PR, tighten any interim
copy that row left soft (e.g. E7c rewords analytics; E1 lets T5 say "in-app").
