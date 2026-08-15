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
  (rendered as "Contains grain (Flour Tortilla)", "Contains grain
  (Breadcrumbs)" — `hiddenReasonLabel` leads with the ltree family).
  Hidden items stay inspectable behind a "show hidden" toggle per group
  (one unnamed group when the menu has no sections — see finding 12).
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
   Root cause is narrower than "no inference": the gap-fill stage already
   asks for "ADDITIONAL ingredient slugs implied by the dish"
   (`ingestion/gap_fill_prompt.rb`), but `DeterministicResolver#gap?` only
   routes items to it on zero matches, leftover phrases, or a condiment
   match — a Margherita that cleanly resolves to mozzarella/tomato/basil
   skips inference entirely, so dough is never added. The fix is widening
   the `gap?` trigger (or an implied-bases pass for cleanly-resolved
   items), not building a new stage. This is the false negative the
   product's credibility hangs on.
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

8. **No password-reset UI on web.** Email+password is the only web auth, and
   `/login` has no forgot-password link or pages. The API half already
   exists — Devise `:recoverable` is mounted (`user.rb`, password routes
   under `/api/v1/auth/`) and production email went live 2026-08-14
   (`launch-readiness.md` §2 counts the reset mailer as live) — so the gap
   is web pages wired to it, not a new flow. Until then a forgotten
   password strands a profile.
9. **Account deletion has no UI.** `DELETE` on the Devise registration
   exists and cascades per the model declarations (the chat cascade is the
   verified part, per the L1 brief; the endpoint itself has no spec), but
   neither web nor mobile surfaces a delete button. Already tracked with
   wider scope as **F2** in `legal-remediation-followups.md` (buttons +
   privacy-copy update + retiring manual `privacy@` fulfillment) — work it
   there, don't fork it here.
10. **Restaurant pages show no address, hours, phone, or website.**
    `phone` and `website` are already in the `#show` payload and typed on
    the web `Restaurant` interface — rendering them is a pure web change
    (the quick win). `street` is only in the `#index` summary serializer,
    so putting the address on the page needs a serializer + rswag/codegen
    change too. Hours exist admin-side only. Today none of it renders —
    users must Google the restaurant they just decided to trust.
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
    - The homepage's "one-tap suggest a restaurant flow" has no UI entry
      point anywhere. The backend exists — `POST /api/v1/restaurants` is
      the Phase 6.2 community "scan a new restaurant" endpoint (with a
      pg_trgm duplicate guard), and mobile ships a tested client helper —
      but no screen or web page calls it, so the promise is unreachable.

## Incidental (dev infra, found while exploring)

13. **`docker compose up` can point the dev API at production Neon.**
    `apps/api/.env` holds the prod `DATABASE_URL`; `compose.yaml` loads it via
    `env_file`, and Rails lets `DATABASE_URL` override `database.yml` for the
    current env — `DATABASE_HOST: postgres` does not win over it. The
    documented "fastest path" (CLAUDE.md, `docs/local-dev.md`) plausibly boots
    dev + `db:prepare` against prod. Same trap already known for local rspec;
    the compose file re-arms it.

## Suggested small fixes (checklist)

PRs in flight are noted; tick items as they merge.

- [ ] `FilterBadge` + rswag enum + `FilterSummary` type: handle
      `profile_token` ("Shared filter" label) — finding 7. (#614)
- [ ] Restaurant page: accept `?profile=<preset>` and pass through SSR fetch +
      client refetches; link `/durango/<diet>` cards with it — findings 5, 6.
      (branch `feature/preset-links`, opens after #614)
- [ ] Distinguish invalid/expired share token from 404 with a friendly
      explainer — finding 7. (branch `fix/share-token-fallback`)
- [ ] Pin the compose stack's `DATABASE_URL` (anchor-level, so the worker
      inherits it too), check in `.env.development` for the native path, and
      correct the in-container spec command — finding 13. (#615)
- [ ] Render `phone` + `website` on the restaurant page (already in the
      `#show` payload) — finding 10's quick win. Street needs the serializer
      change first. (branch `feature/restaurant-contact`)
- [ ] Add a `/durango` index page listing the diet pages; link the diet pages
      from somewhere real — finding 11. (#617)
- [ ] Fix the homepage preset example ("Diabetes-friendly" doesn't exist) —
      finding 12. (#616, which also caught the same copy in the App Store
      listing.) The "30 restaurants" line is NOT a copy fix: seeding 30 is
      an open launch gate (`launch-readiness.md` §6), so either the content
      lands or a human decides to soften the claim — flagging, not editing.
- [ ] Search box on `/restaurants` — finding 11. (#620 — shipped as local
      filtering of the SSR list rather than the API `?q=`: review showed the
      SSR-search version would burn the shared rack-attack bucket and blow
      up the Data Cache key space. `?q=` stays for API/MCP callers.)
- [ ] Web pages for the existing Devise `:recoverable` password reset —
      finding 8.
- [ ] Account deletion UI — tracked as F2 in
      `legal-remediation-followups.md`; tick there, not here — finding 9.

Bigger items (1–4) need product/content work — widening the ingestion
`gap?` trigger so cleanly-resolved items still get implied-base inference,
a confirmation push for Chamayo/RGP's, an ingredients panel on the item
page, and an anonymous entry point to chat/scan — and are left for roadmap
planning rather than this checklist.
