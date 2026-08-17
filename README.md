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
│   ├── filter-engine/   Menu wire types + shared display helpers (web + mobile)
│   ├── analytics/       Funnel-event taxonomy (web + mobile + api)
│   ├── ui-tokens/       Shared design tokens
│   ├── version-history/ Calver release log (YYYY.M.D[.X]) + pnpm bump
│   └── eslint-config/
├── _legacy/         Frozen 2020 Rails 4.2 codebase (read-only)
└── docs/
    ├── adr/         Architecture decision records
    └── ...
```

## Quickstart

Requires Docker, plus Node 22+ and pnpm 10+ for web/mobile (and Ruby 3.3+
only if you run the API natively).

### Option A — containerized API (recommended)

The API, its Solid Queue worker, and Postgres run in Docker; web and
mobile run natively. One command brings the server side up:

```bash
cp apps/api/.env.example apps/api/.env   # optional — only ingestion needs a key
docker compose up                        # API :3000 + worker + Postgres
                                         # first boot installs gems, creates + seeds the DB

pnpm install
pnpm dev                                 # web :3001 + mobile, via Turborepo
```

Edits to `apps/api` hot-reload (source is bind-mounted). `docker compose
down` stops it; add `-v` to also drop the database volume.

### Option B — everything native

```bash
pnpm install
docker compose up -d postgres    # just Postgres 16 in a container
pnpm dev                         # web + mobile

cd apps/api                      # the API is not in the pnpm workspace
bundle install
bin/rails db:prepare             # create + load schema + seed
bin/rails s -p 3000              # web dev server is on :3001
bin/rails solid_queue:start      # background-job worker, in a second terminal
```

See [`docs/local-dev.md`](docs/local-dev.md) for the full local-development
guide. Each app also has its own README under `apps/<name>/`.

## Status

Phase 5 (launch prep): all loop-shippable code is on master; remaining
items need human provisioning — see `docs/launch-readiness.md`. See
`docs/adr/0001-stack.md` for the architectural picks and
`docs/roadmap.md` for the phase plan.
