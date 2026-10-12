# BiteWorthy

> **Scan any menu, see only what you can eat.**

BiteWorthy turns a restaurant menu into a personal shortlist. You say what you
avoid, from allergies and intolerances to religious observance and lifestyle,
and every dish comes back as _safe_ or _hidden, and here is why_. Menus arrive
by photo, PDF, or link; a model reads them into a curated ingredient taxonomy,
a person checks the result, and the filter runs on the server so every client
shows the same answer. Live at [bite-worthy.com](https://bite-worthy.com),
Durango first, with more cities on the way.

## Start here

| You are…                                   | Read                                                                                                                                                   |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| New to the codebase                        | This file, then [`docs/local-dev.md`](docs/local-dev.md) to run it, then [`docs/schema.md`](docs/schema.md) for the data model in 60 seconds.          |
| Working on a specific app                  | That app's `README.md` under `apps/`.                                                                                                                  |
| An agent, or reviewing agent work          | [`AGENTS.md`](AGENTS.md): the rules, the commands CI runs, and the review contract. Every app has its own `AGENTS.md` too.                             |
| Looking for why something is the way it is | [`docs/adr/`](docs/adr/) for the big picks, [`docs/plans/`](docs/plans/) for live work, and [`docs/status.md`](docs/status.md) for the day-by-day log. |
| Looking for what is next                   | [`docs/roadmap.md`](docs/roadmap.md).                                                                                                                  |

## What is in the box

```
biteworthy/
├── apps/
│   ├── api/        Rails 8 JSON API: the filter, the chat, the MCP server, ingestion
│   ├── web/        Next.js 16: the public site, the chat, scanning, /admin
│   └── mobile/     Expo: the diner's app (scan, filter, chat)
├── packages/
│   ├── api-types/        TypeScript types generated from the API's OpenAPI document
│   ├── filter-engine/    Menu wire types + display helpers shared by web and mobile (not a filter)
│   ├── analytics/        The funnel-event taxonomy (a contract with the dashboards)
│   ├── ui-tokens/        Design tokens for Tailwind (web) and StyleSheet (mobile)
│   ├── version-history/  The calver release log behind /updates, written by `pnpm bump`
│   └── eslint-config/
├── docs/           Run book, schema tour, ADRs, plans, the status log (index in docs/README.md)
├── _legacy/        The 2020 Rails 4.2 app. Frozen, read-only.
└── .github/        CI, the API deploy, auto-merge (see .github/README.md)
```

Three surfaces talk to one API:

- **Web** at bite-worthy.com (Vercel): menus, a chat assistant, scanning, and the `/admin` back office.
- **Mobile** (Expo, iOS and Android): the same account, camera-first.
- **MCP** at `api.bite-worthy.com/mcp`: the same tools the chat uses, exposed to any MCP client with OAuth.

The one rule that shapes everything: **the server decides what is safe.**
`Menus::Filter` in the API is the only place a dish becomes visible or hidden,
and the clients render what they receive. See _Architecture_ in
[`AGENTS.md`](AGENTS.md) for the why.

## Quickstart

Requires Docker, Node 22, and pnpm 10. Ruby 3.3.6 only if you run the API
natively.

```bash
cp apps/api/.env.example apps/api/.env   # optional: only ingestion and chat need an Anthropic key
docker compose up                        # API on :3000, its Solid Queue worker, and Postgres
                                         # first boot installs gems and creates + seeds the database

pnpm install
pnpm dev                                 # web on :3001 and mobile, via Turborepo
```

Edits under `apps/api` hot-reload (the source is bind-mounted). `docker
compose down` stops it; add `-v` to drop the database too. For the native
path, the test commands, and the usual snags, see
[`docs/local-dev.md`](docs/local-dev.md).

## Shipping

Every PR gets squash auto-merged the moment its required checks are green.
A merge to `master` that touches `apps/api/` deploys the API to its Hetzner
box through Kamal; Vercel deploys the web app from every push to `master`;
mobile ships through EAS. Releases are calver entries added with
`pnpm bump --note "…"` and rendered at `/updates`. Details in
[`AGENTS.md`](AGENTS.md) and [`.github/README.md`](.github/README.md).

## Where it stands

The web app is live and the product is feature complete for one city. The
mobile app builds through EAS but is not yet in the stores; what is left is in
[`docs/launch-readiness.md`](docs/launch-readiness.md), and the multi-city work
in progress is at the top of [`docs/roadmap.md`](docs/roadmap.md).

Operating entity: Whiteboard Works Software LLC.
