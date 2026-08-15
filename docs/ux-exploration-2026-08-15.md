# User-exploration findings — 2026-08-15

A walkthrough of the live product (`bite-worthy.com` + `api.bite-worthy.com`)
as an anonymous user, plus a code read of the signed-in surfaces. Point-in-time
snapshot: 3 published restaurants, pre-store-launch, web only. Findings are
ordered by severity within each section. Where a finding has an obvious small
fix, it's in the checklist at the bottom.

Method: rendered pages fetched over HTTP (SSR output), live API exercised with
real presets/share tokens/strictness levels, client-only flows (onboarding,
chat, settings) assessed from source. No visual browser pass (extension not
connected) — worth repeating with one for layout/interaction issues.

## What works well

- **The honest-disclosure contract delivers.** `?profile=gluten-free` on
  Chamayo: 28/36 visible, every hidden item carries a specific reason
  ("Contains Flour Tortilla", "Contains Breadcrumbs"). Hidden items stay
  inspectable per-section.
- **Taxonomy search is strong.** "garbanzo" → Chickpeas via aliases, allergen
  flags, `ltree` paths ("msg" → ajinomoto, "shrimp" → prawn, allergen=true).
- **Onboarding is well-engineered**: 5 steps, sessionStorage draft survives the
  login bounce, exit hatch, skippable taste step, disclaimer acknowledgment
  gate before save.
- **Legal surface is thorough**: persistent "a filter, not a guarantee" notice
  on every menu, footer disclaimer, analytics opt-out, no health data in
  identified events.
- **Fast + solid SEO plumbing**: SSR pages in 0.25–0.7s, sitemap/robots/
  canonical/OG on the `/durango/<diet>` pages, clean 404s for unknown slugs.
- **Account page allows in-place preference editing** (presets, strictness,
  avoid lists) — not just redo-the-wizard — plus favorites, my-reviews,
  connected apps, MCP tokens.

## Safety & trust gaps (highest stakes)

1. **Gluten-free passes the pizzas.** Margherita, Pepperoni Sausage, Wild
   Mushroom, San Danielle, Margherita Pizzette are all `visible` under
   celiac/gluten-free at balanced. Margherita
   (`items/2e847269-…` at Chamayo) has 4 tagged ingredients and no dough/crust.
   Systematic ingestion gap: implied base ingredients (pizza dough, cornbread
   flour, breading) aren't inferred, so the filter can't catch them. This is
   the false negative the product's credibility hangs on.
2. **Strict mode renders an empty menu at 2 of 3 restaurants.** Chamayo
   (36 items) and RGP's Wraps (32) have zero `confirmed` associations — strict
   hides everything with `unconfirmed_strict`. Zia Taqueria is fully confirmed
   (18/18), so the pipeline works; the confirmation backlog is the gap. The
   story page explicitly sells strict mode to the highest-stakes users.
3. **No surface shows what the AI thinks is in a visible dish.** The item page
   (`/restaurants/<slug>/items/<id>`) shows name, description, reviews,
   suggest-a-fix — but not detected ingredients, confidence, or source, despite
   the story page promising exactly that ("behind each call is a confidence
   level and a source"). Users can't sanity-check finding #1, and can't see
   what they'd be fixing with suggest-a-fix.

## Funnel breaks

4. **The scan-a-menu promise is unreachable.** Both apps are "coming soon"; on
   web the scan lives in `/chat`, which is login-gated *and* absent from the
   header until signed in. The homepage "📸 Scan the menu" tile isn't a link.
   An anonymous visitor has no path to (or evidence of) the headline feature.
5. **`/durango/<diet>` drops the filter on click-through.** The card says
   "Chamayo — 28 safe items · 8 hidden by your filter" but links to plain
   `/restaurants/chamayo`, which renders "No filter", 36 items. The API already
   supports `?profile=<slug>`; the restaurant page just never accepts a preset
   param (only `?p=<share token>`).
6. **No way to apply a preset on a menu page.** The restaurant page offers only
   a strictness toggle. An anonymous user cannot say "I'm vegan" without
   completing onboarding *and* creating an account — a sign-up wall revealed
   only at the final "Save profile" step.
7. **Share links misreport their own filter.** The items API returns
   `filter.source: "profile_token"`, which `FilterBadge`
   (`RestaurantClient.tsx`) doesn't know — recipients see "No filter ·
   balanced" while items are hidden (confirmed live). The hand-written
   `FilterSummary.source` union in `lib/restaurants.ts` is missing the value
   too. Related: an expired/corrupt token surfaces as a bare 404 (the page
   swallows the API's clean 422 "Invalid profile_token: expired"), and the
   "short" share URL is ~2.3 KB (43 UUIDs, base64).

## Product gaps

8. **No password reset.** Email+password is the only web auth and there's no
   forgot-password flow anywhere (web or API routes). A forgotten password
   permanently strands a profile. (Production email is live since 2026-08-14,
   so the mailer side is unblocked.)
9. **Account deletion has no UI.** `DELETE` on the Devise registration exists
   and cascades correctly (per the 2026-08-14 chat-privacy brief), but the
   settings page has no delete-account button — a legal exposure for
   health-adjacent data, relevant to the open L1 pass.
10. **Restaurant pages show no address, hours, phone, or website.** The API
    already returns `street` (e.g. Zia: "2977 Main Avenue"); admin manages
    hours. None of it renders publicly — users must Google the restaurant they
    just decided to trust.
11. **Orphaned/missing pages.** `/history` and `/u/<handle>` are linked from
    nowhere; `/durango` (no diet) 404s; the diet SEO pages have zero internal
    links (sitemap only). Restaurant search works in the API (`?q=`) but has no
    search box UI.
12. **Content thinness undercuts the copy.**
    - 3 restaurants live vs. "seeding the launch with 30" on the homepage.
    - Zero dish photos anywhere → menus render as walls of 160px monogram
      tiles (the placeholder design assumed partial coverage, not 0%).
    - Menu sections populated at only 1 of 3 restaurants (RGP's Wraps);
      Chamayo and Zia render as one flat A–Z list with no course structure.
    - Zero reviews; "Be the first to review" repeats 36× on a menu page.
    - The homepage advertises a "Diabetes-friendly" preset that doesn't exist
      (live presets: celiac, dairy-free, gluten-free, halal, kosher,
      peanut-allergy, pescatarian, tree-nut-allergy, vegan, vegetarian).
    - The homepage's "one-tap suggest a restaurant flow" exists only in the
      marketing copy — no implementation in web, mobile, or API.

## Incidental (dev infra, found while exploring)

13. **`docker compose up` can point the dev API at production Neon.**
    `apps/api/.env` holds the prod `DATABASE_URL`; `compose.yaml` loads it via
    `env_file`, and Rails lets `DATABASE_URL` override `database.yml` for the
    current env — `DATABASE_HOST: postgres` does not win over it. The
    documented "fastest path" (CLAUDE.md, `docs/local-dev.md`) plausibly boots
    dev + `db:prepare` against prod. Same trap already known for local rspec;
    the compose file re-arms it.

## Suggested small fixes (checklist)

- [ ] `FilterBadge` + `FilterSummary` type: handle `profile_token` ("Shared
      filter" label) — finding 7.
- [ ] Restaurant page: accept `?profile=<preset>` and pass through SSR fetch +
      client refetches; link `/durango/<diet>` cards with it — findings 5, 6.
- [ ] Distinguish invalid/expired share token from 404 with a friendly
      explainer — finding 7.
- [ ] Render `street` (+ city) on the restaurant page — finding 10.
- [ ] Add a `/durango` index page listing the diet pages; link the diet pages
      from somewhere real — finding 11.
- [ ] Pin the compose stack's `DATABASE_URL` to the local container — finding
      13.
- [ ] Fix homepage preset examples ("Diabetes-friendly") and soften the "30
      restaurants" claim to match reality — finding 12.
- [ ] Search box on `/restaurants` wired to the existing `?q=` — finding 11.
- [ ] Surface account deletion in settings — finding 9.
- [ ] Password reset flow — finding 8 (bigger; needs API + mailer + pages).

Bigger items (1–4) need product/content work — ingestion inference of implied
base ingredients, a confirmation push for Chamayo/RGP's, an ingredients panel
on the item page, and an anonymous entry point to chat/scan — and are left for
roadmap planning rather than this checklist.
