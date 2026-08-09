# Six-month plan — reversed into tasks (manual + code)

> The "how do we *win*, not just launch" companion to `docs/launch-plan.md`.
> Reverses the launch plan + strategy (`docs/strategy-2026-h2.md`) into a
> sequenced task breakdown, split **[MANUAL]** (human-only) vs **[CODE]**
> (loop-shippable). Every non-obvious sequencing call is backed by a
> steelman-both-ways decision (§1). Living doc — check items off as shipped.

**Created:** 2026-07-14 · **Horizon:** July → December 2026 · **Status:** pre-launch (code-complete, credential-gated)

---

## The meta-conclusion

The binding constraint is the **human launch timeline (~2–4 weeks of
provisioning + attorney sign-off that cannot be compressed)**. Everything else
is loop-shippable code that should run *inside* that window and then be gated on
real canaries — not the 2026-06-18 strategy hunches.

All three strategic debates below resolve to the same shape:
**parallelize the human and code tracks, then gate every subsequent build on
evidence.** Use the unavoidable launch-prep window to pre-build the retention
hook + the safety guardrails + SEO; launch small; then let the three canaries
(§4) drive discovery, gamification, monetization, and city #2.

---

## 1. The three decisions (steelman both ways → verdict)

### A. Sequencing — launch thin now, or build the retention loop first?
- **Steelman "launch now":** Frequency is unproven; the fastest way to learn is
  real users. Every week pre-building a loop nobody has validated is a week of
  guessing. Ship, measure, then build what the data demands.
- **Steelman "loop first":** A high-value/low-frequency tool with no retention
  hook churns its first cohort — and you only get one first impression with a
  small Durango word-of-mouth base. Launching into an empty-menu, one-and-done
  experience burns the scarce early audience.
- **Verdict — overlap them.** The human launch path takes ~2–4 weeks regardless;
  that window is free build time. Launch on the Track A timeline, but pre-build
  *exactly one* retention hook (the confirm/dispute ✓/✗ micro-loop) + the
  anonymous filter picker so day-one strict users never hit an empty page. Defer
  the gamified contribution *identity* until the micro-loop shows engagement.

### B. Positioning — discovery-led for everyone, or safety-first wedge?
- **Steelman "discovery-led":** "What should I order?" fires for ~everyone at
  every restaurant — 3–4× the TAM and the only mass-market answer to the
  frequency problem. The scoring engine is already built (Phase 8); it's a
  frontend reorder, not a new product.
- **Steelman "safety-first wedge":** Honest disclosure is the *only* moat — the
  one thing EveryBite/Olo and the grocery scanners structurally can't copy.
  Leading with generic discovery throws away the defensible identity and invites
  a Yummly-style "discovery without grounding wasn't defensible" death.
- **Verdict — sequence, don't choose.** Keep the wedge-first identity (safety,
  restricted diners) as the launch headline. Ship discovery only as a Top Picks
  layer *inside* already-safe menus. Flip the headline to "what should I order?"
  only if **rec-acceptance clears a bar (~30% tap/save) with the safety canaries
  green**. Instrument rec-acceptance from day one so the pivot is a data call,
  not a vibe.

### C. Trust vs. scale — is honest disclosure enough, or harden before opening?
- **Steelman "enough":** The confidence/source model + strict mode + "show why"
  already encode safety in the schema. Over-hardening before you have users is
  premature; ship and add guards when scale demands them.
- **Steelman "harden first":** One cross-contamination incident is existential
  (strategy §6). The false-negative — a hidden allergen rendered as safe — is
  "the one unforgivable bug." At scale, community publishing invites vandalism
  the 80%-threshold can't catch.
- **Verdict — guard the fatal mechanism now, defer scale-gated hardening.** The
  three guardrail tests (parity, array-sync, adversarial hidden-allergen) are
  near-free and CI-blocking → **P0 before launch**. Anti-vandalism /
  trusted-contributor weighting only matters at scale → **P1, gated on leaving
  Durango**. Cross-contamination disclaimer copy reviewed at L1.

---

## 2. The reversed task plan

Tags: **[MANUAL]** = human-only · **[CODE]** = loop-shippable · P0/P1/P2 = priority.

### Phase 0 — The launch window (Weeks 0–4): two streams in parallel

**Stream 1 — [MANUAL] Track A critical path** (the real gate; detail in `docs/launch-plan.md`)
- [ ] **Provision Hetzner cx22 → Neon → GHCR PAT → first `kamal deploy`** (keystone)
- [ ] **Engage the L1 attorney on `/privacy` + `/terms` — day one** (long lead; blocks DRAFT-banner removal + store submission). Also get the **L3 dish-photo auto-crop liability ruling**.
- [ ] **Enable Anthropic billing**
- [ ] **Apple Developer ($99) + Google Play ($25) + DMCA agent ($6)**; **design `icon-source.svg`**
- [ ] **Postmark SMTP · Cloudflare R2 · Vercel (domain + SSR) · PostHog API key**
- [ ] **Seed 30 Durango restaurants (~$15 ingestion)** — coverage *is* the day-one product
- [ ] **Set up Neon snapshots** — ADR-0007 admits no self-snapshot today; one un-backed-up wipe during early word-of-mouth is a pre-mortem death. Don't launch without it.
- [ ] **Gate: verify strict-mode `visible_count` is non-trivial on seeded data *before* inviting anyone** (the empty-menu check)

**Stream 2 — [CODE] pre-launch, ships during the window**
- [ ] **[P0] The three safety guardrails** — highest-value code in the plan:
  - ~~Parity test: `packages/filter-engine` output ≡ API SQL filter~~ — **dropped Aug 2026.** There is no second filter to hold in parity: the TS mirror had no callers and was deleted, and its "parity" test compared TS to TS. What this item was really after is an adversarial fixture set (allergen present/absent × strict on/off) asserted against `Menus::Filter` — which is the bullet below.
  - Array-sync invariant + nightly reconciliation: `items.ingredient_ids/tag_ids` always equal the join rows; alert on drift
  - Adversarial test: a `suggested`/self-accepted item with a hidden allergen must **never** render safe for a user avoiding it, in any mode
- [ ] **[P0] Anonymous filter picker on `/r/<slug>` + `localStorage`** — kills the empty-first-impression risk (backend already supports `?profile=`/`?profile_token=`)
- [ ] **[P0] Confirm/dispute "✓/✗" micro-loop** → writes a suggestion/verification. The *one* retention hook; also backfills strict-mode confirmations (fixes sparsity). Not the gamified identity yet.
- [ ] **[P0] Instrumentation before first user:** week-2 return rate, strict-mode `visible_count`, coverage velocity, **rec-acceptance** (tap/save on a Top Pick)
- [ ] **[P1] Visibility / SEO:** populate `restaurantSlugs` in the sitemap, add `generateMetadata` + Restaurant/Menu JSON-LD, forward diet context from durango cards (`?profile=<diet>`). SEO compounds — start early.
- [ ] **[P1] QR Phase 1 (web-only)** — encode `https://<host>/r/<slug>`; owner-independent distribution, zero install
- [ ] **[P1] Top Picks row *inside* safe menus only**, labeled provisional (discovery as a within-safety layer)
- [ ] **[MANUAL] Copy review:** cross-contamination + "not a medical guarantee" disclaimers reviewed at L1 — never let marketing say "safe"

### Phase 1 — Soft launch & learn (Month 1–2)
- [ ] **[MANUAL] Soft-launch to Durango restricted diners**; watch the three canaries ~2–3 weeks before any wider push
- [ ] **[MANUAL] Founder spot-audit** the first community-published restaurants
- [ ] **[CODE]** Finish **anonymous onboarding** (avoid-list → `profile_token` in `localStorage`, "save to account" offered *after*) so building a filter no longer requires signup
- [ ] **[CODE]** Keep onboarding **dietary-first**; taste is an optional/skippable step (not step 1 yet)
- [ ] **[CODE] QR Phase 2 (deep-link)** — add `associatedDomains` + `intentFilters` + AASA/assetlinks, once the **Apple Team ID + Android signing SHA** exist from the store accounts
- [ ] **[MANUAL]** Write the **pivot gate** into the strategy doc: widen the front door only if rec-acceptance ≥ threshold **AND** safety canaries green

### Phase 2 — The retention loop (Month 3, highest-leverage build)
- [ ] **[CODE]** Contribution identity on `/u/[handle]` (confirmation count, "menus you keep accurate," city rank) — **only if the ✓/✗ micro-loop showed engagement**
- [ ] **[CODE]** Verify the loop raises strict-mode coverage *and* repeat visits
- [ ] **Decision gate:** is week-2 return rate trending up? If not, this loop is the whole ballgame — iterate here before anything else.

### Phase 3 — Frequency + the positioning decision (Month 4)
- [ ] **[MANUAL] Month-4 review: decide the discovery-led repositioning on the rec-acceptance metric, not vibes**
- [ ] **[CODE]** If the gate passed: forced-choice **taste quiz** (flagged, dark-launched first), starter taste profiles, discovery-led onboarding reorder
- [ ] **[CODE]** "Safe near me" / "what should I order near me" (needs `expo-location`)
- [ ] **[CODE][P1] Trusted-contributor weighting + spam/vandalism gate** — required **before** any city beyond Durango (≥2 independent verifiers or 1 trusted for auto-publish)

### Phase 4 — Monetize + harden (Month 5)
- [ ] **[CODE]** Freemium gate: free = N scans/mo + filtering; premium (~$20–30/yr) = unlimited scans, multi-profile, strict mode, offline, **table/group mode** (the last only after rec-acceptance is proven)
- [ ] **[MANUAL] Set up billing** (App Store / Play IAP or Stripe) — new manual item for premium
- [ ] **[CODE]** Fix the analytics/throttle **IP-bucketing race** (shared store, not per-process MemoryStore) before scaling
- [ ] **[CODE]** Harden monitoring: alert on `visible_count` anomalies and on any post-publish edit that *removes* an allergen (tampering/error signal)

### Phase 5 — Expand on evidence (Month 6)
- [ ] **[MANUAL] Expand to city #2 only if the week-2 canary went green** after the Month-3 loop; pick it by where waitlist/organic interest clusters

---

## 3. Dependency shape

```
[MANUAL] provision ──► kamal deploy ──► seed Durango ──► visible_count gate ──► SOFT LAUNCH
   │                                                          ▲
   │  (runs in parallel, same 2–4 wk window)                  │
[CODE] P0 guardrails ─► anon picker ─► ✓/✗ micro-loop ─► instrumentation ──┘
[CODE] SEO + QR Ph1 ──────────────────────────────────────► (compounds post-launch)

SOFT LAUNCH ──► week-2 canary ──► Month-3 retention loop ──► [gate] ──► discovery pivot / near-me
                                                              │
                                                              └─► [gate] ──► monetize ──► city #2
```

## 4. What "winner in 6 months" means (the scoreboard)

Three numbers decide it (strategy §5); everything above is in service of them:
1. **Week-2 return rate** ≥ ~15% (frequency canary) — the retention loop's job
2. **Coverage velocity** positive and compounding (menus scanned/week via users) — the moat
3. **Strict-mode `visible_count`** non-trivial (the safest users see real options) — the trust check

Plus two pass/fail guards: **zero safety incidents** (P0 tests hold) and
**rec-acceptance measured** before any discovery pivot.

## 5. Decision gates (don't build ahead of these)

| Gate | Unlocks | Metric |
|---|---|---|
| `visible_count` non-trivial on seed | Invite the first users | Strict-mode visible count > 0 across seeded venues |
| ✓/✗ micro-loop shows engagement | Build the contribution *identity* (Ph 2) | Confirmations/user trending up |
| Week-2 return rate green | Frequency surfaces + expansion | ≥ ~15% |
| Rec-acceptance ≥ ~30% + safety green | Discovery-led repositioning (Ph 3) | Top-Pick tap/save rate |
| Anti-vandalism gate shipped | Any city beyond Durango | Trusted-contributor weighting live |

---

## Outstanding manual items (still human-only — none loop-shippable)

- [ ] **Provisioning → first `kamal deploy`** (keystone)
- [ ] **Engage L1 attorney now** (keystone, long lead) + **L3 dish-photo ruling**
- [ ] **Anthropic billing**; **Apple + Google + DMCA**; **design icon SVG**; **seed 30 Durango**
- [ ] **Set up Neon snapshots** (no backup exists today — real data-loss risk)
- [ ] **Verify strict-mode `visible_count` before inviting anyone**
- [ ] **For QR Phase 2:** capture **Apple Team ID + Android signing SHA** at store-account setup
- [ ] **Month-4:** make the discovery-pivot call on data; **Month-5:** set up billing; **Month-6:** city-#2 go/no-go on the canary
