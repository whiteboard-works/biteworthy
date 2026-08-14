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

**Make the contribution loop the product's heartbeat, freemium the business
model — and open the front door to *everyone*, not just restricted diners.**

**Positioning (decided 2026-06-18 — discovery-led, safety underneath):**

> Biteworthy tells you what to order at any restaurant — and if you have
> restrictions, it never shows you what you can't eat.

The headline question becomes **"what should I order here?"** (universal),
with dietary restrictions demoted to an optional *setting*. Restrictions are no
longer the product's identity; they're a guarantee underneath it. See §7.

1. **Coverage via crowdsourcing (the moat).** Anyone-can-scan already shipped
   (Phase 6). Every user who scans a new menu *creates* coverage — HappyCow's
   compounding loop, accelerated by AI tagging.
2. **Frequency via a contribution identity (the retention fix).** Turn
   `suggestion_submitted` + self-verify into "I'm the person who keeps my city's
   menus accurate." Public profiles (`/u/[handle]`) already exist.
3. **Reach via taste discovery (the TAM unlock).** "What should I order?" fires
   for ~everyone at every new restaurant — the mass-market answer to the
   frequency problem the restricted-only loop can't reach. The scoring engine is
   already built (§7).
4. **Revenue via consumer freemium (the proven model).** Yuka: ~98% of revenue
   from subs, ad-free. **Avoid the restaurant-ad trap** (Find Me Gluten Free's
   founder: "almost impossible"). Premium = unlimited scans, multi-profile
   (family), strict mode, offline, and **table/group mode** (§7).

---

## 4. The 6-month plan (June → December 2026)

### Month 1 (June) — Unblock launch. *No new product code.*

- [ ] **L1 attorney sign-off** on `/privacy` + `/terms` → remove DRAFT banners (hard gate)
- [ ] **L3 dish-photo liability** — counsel ruling on auto-cropping third-party menu photos; decide now (opt-in-upload fallback exists)
- [ ] Provision in dependency order: Hetzner cx22 → Neon → GHCR PAT → Kamal deploy
- [x] Resend SMTP (Devise reset, claim verification, waitlist) — live 2026-08-14, smoke delivered to inbox
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
- [ ] **Discovery-led onboarding (§7)** — frontend-only, can build during Month-1 provisioning (no credential dependency): reorder so the **taste quiz is step 1**, dietary becomes an optional setting
- [ ] Build the **forced-choice taste quiz** (~6–10 taps) writing to existing `liked_tag_ids`; keep skippable after ~3 taps
- [ ] Add **starter taste profiles** (taste analog of dietary presets)
- [ ] Instrument **rec acceptance** (tap/save on a Top Pick) — the discovery-quality metric

### Month 3 (Aug) — The contribution loop *(highest-leverage build)*.

- [ ] **Confirm/dispute surface** on every item ("Does this contain X? ✓/✗") → writes a `suggestion`/verification
- [ ] **Contribution identity** on `/u/[handle]`: confirmations count, "menus you keep accurate," city rank (no tiered levels)
- [ ] Verify the loop raises strict-mode coverage (fixes Month-2 sparsity) *and* drives repeat visits

### Month 4 (Sep) — Frequency surface beyond the venue lookup.

- [ ] **"Safe near me"** — given avoid lists + location, what can I eat *right now* across nearby venues
- [ ] **"What should I order?" near me** — taste-ranked picks across nearby venues (discovery analog)
- [ ] **Household/multi-profile + table/group mode (§7)** — combine taste profiles → "what should we all get?" (first premium hook)

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

## 7. Expansion bet — the taste recommender for everyone (discovery-led)

**The idea:** serve the ~70% of diners with *no* dietary restrictions by
answering "what's the best thing to order at this new restaurant?" via a fast
taste-profile quiz. This is the mass-market frequency answer (§1) and roughly
3–4× the addressable audience.

**Why it's cheap: the engine already exists (Phase 8).** This is a frontend
reorder + a better onboarding UX on top of finished infrastructure — not a new
product.

| Already built | File |
|---|---|
| Taste model — `liked/disliked_{tag,ingredient}_ids` arrays, disjoint-set validated | `apps/api/app/models/user_profile.rb:8` |
| `PATCH /api/v1/profile` already accepts taste arrays (no schema/API change) | `apps/api/app/controllers/api/v1/profiles_controller.rb:62` |
| Scoring engine: `+2/liked tag, +1/liked ing, −2/−1 disliked` + rating | `apps/api/app/services/taste_scoring.rb` |
| **"Filter wins"** — avoid lists subtracted *before* scoring (safety guaranteed) | `taste_scoring.rb:37` |
| Regression fixture pinning the scoring arithmetic to 4dp | `packages/filter-engine/fixtures/taste-parity.json` (read by `spec/services/taste_scoring_spec.rb`) |
| Top Picks UI + "Because you like X & Y" reasons (web + mobile), hides for zero-signal | `apps/web/.../TopPicksRow.tsx`, `items_controller.rb:154` |
| Taste tags separable from dietary via `families` param (`cuisine`/`prep`/`flavor` vs `diet`/`allergen`) | `apps/api/app/models/tag.rb:2` |

**Quiz flow spec:** see `docs/plans/taste-quiz.md` (screen-by-screen, reducer
actions, the thin-flavor-taxonomy prerequisite).

**The gap (UX + positioning only):**
- Taste is buried — onboarding is dietary-first; taste is **skippable step 4**
  (`apps/web/src/app/onboarding/page.tsx:224`). Discovery-led → **taste becomes
  step 1, dietary becomes an optional setting.**
- Capture is a cold chip/search picker, not a quiz. Build a **forced-choice
  visual wizard** (~6–10 taps: "which would you order?") that writes the *same*
  `liked_tag_ids`. Keep it skippable/progressive — let users in after ~3 taps.
- No profile-edit UI, append-only, no **starter taste profiles** (the taste
  analog of dietary presets) — add these.

**Killer premium feature — table/group mode:** combine several taste profiles →
"order these 4 dishes the whole table will love." Group-ordering paralysis is
universal (MFP: 80%+ find restaurant choices hard).

**The two guardrails:**
1. **Don't let discovery erode safety trust.** Strict-mode / honest-disclosure
   must stay rock-solid for restricted users even as marketing goes wide. Safety
   is the moat; discovery is the funnel.
2. **Higher rec-quality bar.** Foodies just want the pick to be *good*;
   tag-overlap scoring is a fine v1 but thin. **Instrument rec acceptance** (did
   they tap/save the pick?) from day one; plan collaborative filtering once there
   is data. Remember Yummly ($100M, shut down Dec 2024) — discovery without
   per-venue grounding wasn't defensible. Our grounding (real item data for the
   actual menu) is the defense; never lose it.

---

## Log

- **2026-06-18** — Doc created from strategic review (internal product brief + competitive landscape research). Direction confirmed with Skylar: pure utility filter tool, **not** a game. Core bet = contribution loop + consumer freemium.
- **2026-06-18** — Added §7 taste-recommender expansion. Decision: **discovery-led, safety underneath** — open the app to non-restricted diners via a taste quiz; restrictions become an optional setting. Key finding: the Phase 8 scoring engine is already built; the gap is UX + positioning (reorder onboarding, build a forced-choice quiz, add starter profiles). Premium unlock = table/group mode.
