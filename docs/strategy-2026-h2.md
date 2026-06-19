# Biteworthy — Strategic Review & 6-Month Plan (2026 H2)

> Working strategy doc. Check items off as we ship them. Newest learnings go in
> the **Log** at the bottom. This is a living document — update the diagnosis if
> the data contradicts it.

**Created:** 2026-06-18 · **Horizon:** June → December 2026 · **Status:** pre-launch (code-complete, credential-gated)

---

## 1. The one diagnosis that matters

Biteworthy is a **high-value, low-frequency** tool. The build is strong and
nearly done — Rails 8 API + AI ingestion pipeline, hierarchical taxonomy (~1,096
ingredients), strict-mode confidence model, taste ranking, reviews, ownership
claims, web + Expo mobile, tests green. We are **code-complete and
credential-gated** for a Durango launch.

The risk specific to our shape of product:

> A pure "what can I eat at this restaurant?" lookup is used **once per venue,
> occasionally**. Every app that escaped this trap — Yuka (80M users, ~25k/day
> organic), HappyCow (1.2M contributors over 25 yrs), Fig, MyFitnessPal — did it
> by adding **either a daily-repeatable action or a contribution identity**. None
> of the allergy incumbents (Spokin, AllergyEats, Find Me Gluten Free) cracked
> frequency, and they have stayed small because of it.

v1 correctly defers gamification (no streaks/levels). But "no gamification" ≠ "no
engagement loop." The highest-leverage move in the next 6 months is converting
our **already-built `suggestions` + verification system** into a Yuka/HappyCow-style
contribution loop — turning episodic lookups into a habit *and* compounding the
data moat.

**This is a frequency problem disguised as a launch problem.**

---

## 2. Competitive position — the wedge is real and unoccupied

| Competitor type | Examples | Fatal limitation |
|---|---|---|
| Venue-level review apps | Spokin, AllergyEats, Yelp/Google | Rate the *restaurant*, not the *dish*; Google: ~87% of venues have no dietary attributes |
| Grocery scanners | Yuka, Fig | Wrong location — only ~15 restaurants |
| B2B menu platforms | **EveryBite → Olo** (the real threat) | Restaurant-side; cannot serve venues that never opted in |

**Biteworthy = item-level + owner-independent + honest-disclosure.** No one else
has all three. AI ingestion needs zero restaurant cooperation — the demand side
EveryBite/Olo structurally cannot reach. Honest disclosure (show *why* an item is
hidden + confirmed-only strict mode) is the best answer to the category's #1
objection: *"AI can't be trusted with allergies."*

⚠️ **The clock:** EveryBite joined Olo's ecosystem (750+ brands, 89k locations) in
Nov 2025. They will own the B2B/ordering-integrated side. Our defensible ground is
**consumer-side, owner-independent coverage** — race there, do not try to out-B2B them.

---

## 3. The core strategic bet

**Make the contribution loop the product's heartbeat, and freemium the business model.**

1. **Coverage via crowdsourcing (the moat).** Anyone-can-scan already shipped
   (Phase 6). Every user who scans a new menu *creates* coverage — HappyCow's
   compounding loop, accelerated by AI tagging.
2. **Frequency via a contribution identity (the retention fix).** Turn
   `suggestion_submitted` + self-verify into "I'm the person who keeps my city's
   menus accurate." Public profiles (`/u/[handle]`) already exist.
3. **Revenue via consumer freemium (the proven model).** Yuka: ~98% of revenue
   from subs, ad-free. **Avoid the restaurant-ad trap** (Find Me Gluten Free's
   founder: "almost impossible"). Premium = unlimited scans, multi-profile
   (family), strict mode, offline.

---

## 4. The 6-month plan (June → December 2026)

### Month 1 (June) — Unblock launch. *No new product code.*

- [ ] **L1 attorney sign-off** on `/privacy` + `/terms` → remove DRAFT banners (hard gate)
- [ ] **L3 dish-photo liability** — counsel ruling on auto-cropping third-party menu photos; decide now (opt-in-upload fallback exists)
- [ ] Provision in dependency order: Hetzner cx22 → Neon → GHCR PAT → Kamal deploy
- [ ] Postmark SMTP (Devise reset, claim verification, waitlist)
- [ ] Cloudflare R2 bucket (review + dish photos)
- [ ] Vercel (bite-worthy.com domain + SSR restaurant pages)
- [ ] PostHog API key (funnel measurement)
- [ ] Apple Developer ($99) + Google Play ($25) + DMCA agent ($6)
- [ ] Record the ingestion cassette (~$0.05) so CI greens on real ExtractMenuJob
- [ ] Seed 30 Durango restaurants (~$15 ingestion) — coverage *is* the day-one product

### Month 2 (July) — Launch Durango + instrument honestly.

- [ ] Ship to one zip code. Do not scale — *learn*.
- [ ] Add the one derived metric the 9-event funnel is missing: **week-2 return rate** (the frequency canary)
- [ ] Watch `menu_filtered.visible_count` in strict mode — near-zero confirms the sparsity risk

### Month 3 (Aug) — The contribution loop *(highest-leverage build)*.

- [ ] **Confirm/dispute surface** on every item ("Does this contain X? ✓/✗") → writes a `suggestion`/verification
- [ ] **Contribution identity** on `/u/[handle]`: confirmations count, "menus you keep accurate," city rank (no tiered levels)
- [ ] Verify the loop raises strict-mode coverage (fixes Month-2 sparsity) *and* drives repeat visits

### Month 4 (Sep) — Frequency surface beyond the venue lookup.

- [ ] **"Safe near me"** — given avoid lists + location, what can I eat *right now* across nearby venues
- [ ] **Household/multi-profile** filtering (also the first premium hook)

### Month 5 (Oct) — Monetize + harden.

- [ ] **Freemium gate:** free = N scans/month + filtering; premium (~$20–30/yr) = unlimited scans, multi-profile, strict mode, offline
- [ ] Fix analytics/throttle IP-bucketing race (web shares one Vercel IP → `X-Forwarded-For` + shared store, e.g. Solid Cache/Redis)
- [ ] Replace per-process MemoryStore throttle with a shared store
- [ ] Spam/vandalism gate on the 80%-auto-publish threshold before opening beyond Durango

### Month 6 (Nov–Dec) — Expand to city #2 on evidence.

- [ ] Expand **only if** the week-2 return-rate canary went green after the Month-3 loop
- [ ] Pick city #2 by where waitlist/organic interest clusters
- [ ] Evaluate the Yuka "activism" lever — let users push restaurants to confirm/correct their own menus

---

## 5. The three numbers on the wall

1. **Week-2 return rate** — the frequency canary. If <15% pre-loop, the Month-3 contribution loop is the whole ballgame.
2. **Coverage velocity** — new menus ingested/week via users (the compounding moat).
3. **Strict-mode `visible_count`** — the trust/utility check; near-zero means honest-disclosure is failing the users who need it most.

---

## 6. The honest risks

- **Frequency is unproven** — the entire retention thesis rests on the Month-3 loop. Launch small *specifically* to test it cheaply.
- **EveryBite/Olo** will own B2B; do not chase them — own consumer/owner-independent coverage.
- **Strict-mode sparsity** could churn our safest users first. The loop must backfill confirmations faster than users hit empty menus.
- **AI false-confidence liability** — honest disclosure is the shield; never let marketing oversell "safe." One cross-contamination incident becomes existential.

---

## Log

- **2026-06-18** — Doc created from strategic review (internal product brief + competitive landscape research). Direction confirmed with Skylar: pure utility filter tool, **not** a game. Core bet = contribution loop + consumer freemium.
