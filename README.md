# BiteWorthy

> **Scan any menu, see only what you can eat.**

A pocket food filter that turns any restaurant menu — independent or chain —
into a personalized shortlist in seconds. Built around dietary needs first:
allergies, intolerances, religious observance, lifestyle.

## Repository layout

```
biteworthy/
├── apps/
│   ├── api/         Rails 8 JSON API
│   ├── web/         Next.js 15 (App Router)
│   └── mobile/      Expo / React Native
├── packages/
│   ├── api-types/       TS types generated from the Rails OpenAPI spec
│   ├── filter-engine/   Shared dietary-filter logic (web + mobile)
│   ├── analytics/       Funnel-event taxonomy (web + mobile + api)
│   ├── ui-tokens/       Shared design tokens
│   └── eslint-config/
├── _legacy/         Frozen 2020 Rails 4.2 codebase (read-only)
└── docs/
    ├── adr/         Architecture decision records
    └── ...
```

## Quickstart

Requires Ruby 3.3+, Node 22+, pnpm 10+, Docker (or a local Postgres 16+).

```bash
pnpm install
docker compose up -d postgres    # local Postgres 16 for the API
pnpm dev                         # boots web + mobile concurrently via Turborepo

# The Rails API is not part of the pnpm workspace — boot it separately:
cd apps/api
bundle install
bin/rails db:create db:schema:load db:seed
bin/rails s -p 3000              # web dev server is on :3001
```

Each app also has its own README under `apps/<name>/`.

## Status

Phase 5 (launch prep): all loop-shippable code is on master; remaining
items need human provisioning — see `docs/launch-readiness.md`. See
`docs/adr/0001-stack.md` for the architectural picks and
`docs/roadmap.md` for the phase plan.
