# Roadmap

The phase plan that gates every PR. Each phase ends with a real demo,
not a "feature complete" claim.

## Phase 0 — Foundation ✅ in progress

- [x] Archive 2020 codebase to `_legacy/`
- [x] pnpm + Turborepo monorepo
- [x] Rails 8 API skeleton (config, schema, models, seeds)
- [x] Next.js 15 web skeleton
- [x] Expo mobile skeleton
- [x] Shared TS packages: api-types, filter-engine (with tests),
      ui-tokens, eslint-config
- [x] CI: GitHub Actions for JS + Rails
- [x] ADR 0001 capturing every stack pick
- [ ] `pnpm install` + `bin/setup` + `pnpm dev` boot all three apps

**Demo:** all three apps say "hello" against the same Rails API.

## Phase 1 — Schema + auth + admin (weeks 2–3)

- [ ] Devise JWT login / signup / refresh endpoints
- [ ] Apple + Google OAuth round trips
- [ ] User profile (avoid/prefer/strictness) read + update endpoint
- [ ] Admin dashboard (Rails-side, ERB) for cities, restaurants,
      ingredients, tags, dietary profiles
- [ ] Full ~1500-row ingredient port from `_legacy/db/seeds/0_ingredients.rb`
      into structured YAML
- [ ] OpenAPI spec via rswag → generates `packages/api-types`
- [ ] Restaurant + item read endpoints with the dietary-filter scope wired
      into Active Record

**Demo:** admin creates a restaurant + a 10-item menu by hand; mobile and
web both render it; toggling a dietary profile changes what's shown.

## Phase 2 — AI ingestion MVP (weeks 4–6) ⭐

- [ ] AnthropicClient service (Faraday + Bearer + prompt caching)
- [ ] IngestionRun + IngestionItem state machine
- [ ] Solid Queue jobs: ExtractMenu, ResolveIngredients, ResolveTags
- [ ] Mobile: multi-page camera capture → upload → wait → swipe-verify UI
- [ ] Web: paste URL or upload PDF → verify
- [ ] Cost + latency dashboard in admin

**Demo:** photograph a real Durango menu in person; 60 seconds later the
items appear staged; 5 minutes of swiping promotes them to live.

## Phase 3 — Dietary filter (weeks 7–9)

- [ ] Profile onboarding (6 taps to working filter)
- [ ] Curated dietary-profile presets fully wired
- [ ] Filtered restaurant page (mobile + web) — applyProfile from
      filter-engine
- [ ] Transparency layer: every hidden item shows reason
- [ ] One-tap override per item ("show anyway")
- [ ] Strict-mode toggle (hides anything not `confidence: confirmed`)
- [ ] Shareable filter URLs (encode profile in a token)

**Demo:** open the app, pick "Celiac + tree-nut allergy", scan a real
menu, see only the dishes that pass. Hidden items each say *why*.

## Phase 4 — Reviews + accounts (weeks 10–11)

- [ ] Per-item reviews (1–5 + text + photo)
- [ ] Review moderation queue
- [ ] User profile pages
- [ ] "My filtered menus" history
- [ ] Restaurant claim flow (domain-email verification)
- [ ] Suggestion queue UX for community edits

**Demo:** a logged-in user reviews a dish from a restaurant they
filtered to; an owner claims that restaurant.

## Phase 5 — Launch (week 12)

- [ ] Seed 30 Durango restaurants via the ingestion pipeline
- [ ] App Store + Play Store submission
- [ ] SEO landing pages: `/durango/gluten-free`, `/durango/vegan`, etc.
- [ ] PostHog funnels: app_open → profile_set → menu_filtered →
      restaurant_tap
- [ ] Public launch posts + outreach to Durango press

**Demo:** real users on a Friday night using it to pick where to eat.

## What we are explicitly NOT doing in v1

- 14-tier user levels / gamification
- Restaurant-deal coupons
- Reservations / delivery integrations
- Social feed
- A separate native iOS / native Android codebase
