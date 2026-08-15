# Local development

How to run BiteWorthy on your machine. Two supported paths: a
**containerized** server side (recommended) or **everything native**.

- **API** (Rails 8) — containerized or native.
- **Web** (Next.js, port `3001`) — native (`pnpm dev`). Talks to the API
  on `:3000`.
- **Mobile** (Expo) — always native. Expo needs simulator/device access
  and a Metro bundler that don't containerize cleanly.

The data model and the apps are described in [`README.md`](../README.md),
[`schema.md`](schema.md), and each app's own `README`. This file is just
the run book.

## Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| Docker (Desktop or Engine) | recent | Postgres, and the containerized API |
| Node | 22+ | web + mobile |
| pnpm | 10+ | web + mobile (`corepack enable` or `npm i -g pnpm`) |
| Ruby | 3.3.6 | only if running the API **natively** |

`.nvmrc` and `.ruby-version` pin the exact versions.

## Option A — containerized API (recommended)

The API, its Solid Queue worker, and Postgres run in Docker; web and
mobile run natively.

```bash
cp apps/api/.env.example apps/api/.env   # optional — see "Environment" below
docker compose up                        # API :3000 + worker + Postgres

pnpm install
pnpm dev                                 # web :3001 + mobile, via Turborepo
```

What `docker compose up` does:

- **`postgres`** — Postgres 16, bound to `127.0.0.1:5432`, trust auth,
  data persisted in the `pgdata` named volume.
- **`api`** — builds the `dev` stage of `apps/api/Dockerfile`, then on
  every boot clears any stale Puma pid, runs `bundle check || bundle
  install` (self-heals after a Gemfile change), runs `bin/rails
  db:prepare` (creates + loads schema + **seeds on first run**), and
  boots Puma on `0.0.0.0:3000`. Health-checked at `/up`.
- **`worker`** — same image, runs `bin/rails solid_queue:start`. Waits
  for `api` to be healthy so the queue schema exists before it polls.

`apps/api` is bind-mounted into the container, so code edits hot-reload
via Rails' dev reloader — no rebuild needed. Gems live in a named
`bundle` volume (seeded from the image), so they persist across restarts.

First boot pulls the Ruby image, installs gems, and seeds the DB — a few
minutes. Later boots are seconds.

### Everyday commands

```bash
docker compose up -d                 # start in the background
docker compose logs -f api           # tail API logs (or: worker, postgres)
docker compose ps                    # what's running + health

docker compose exec api bash                         # shell in the API container
docker compose exec api bin/rails console            # Rails console
docker compose exec api bundle exec rspec            # run the test suite
docker compose exec api bin/rails db:migrate         # run a new migration
docker compose exec api bin/openapi-export           # regenerate docs/openapi.json

docker compose down                  # stop (keeps the DB volume)
docker compose down -v               # stop AND drop pgdata + bundle volumes (full reset)
docker compose up -d --build         # rebuild after a Gemfile / Dockerfile change
```

> Rebuild the image (`--build`) when you change the `Gemfile`/`Dockerfile`.
> A plain restart self-heals gems via `bundle check`, but rebuilding bakes
> them into the image so the next clean boot is fast.

## Option B — everything native

Run only Postgres in a container; everything else on the host.

```bash
pnpm install
docker compose up -d postgres        # just Postgres 16

cd apps/api                          # the API is NOT in the pnpm workspace
bundle install
bin/rails db:prepare                 # create + load schema + seed (idempotent)
bin/rails s -p 3000                  # API on :3000
bin/rails solid_queue:start          # background-job worker, second terminal
```

Then `pnpm dev` from the repo root for web + mobile.

Postgres needs the `ltree`, `pg_trgm`, `pgcrypto`, and `citext`
extensions. The migrations enable them, but the role needs `CREATE
EXTENSION` rights the first time (the containerized `postgres` superuser
has them already).

## Environment

`apps/api/.env` (gitignored) holds local secrets; `apps/api/.env.example`
is the canonical, commented template. The stack **boots without it** —
every value has a dev default or fallback.

You only need a value to exercise the feature it gates:

| Variable | Needed for |
|---|---|
| `ANTHROPIC_API_KEY` | the AI menu-ingestion pipeline (`docs/ingestion.md`) |
| `GOOGLE_OAUTH_*`, `APPLE_OAUTH_*` | real social sign-in flows |

In the container, `DATABASE_HOST` is set to the `postgres` service name by
`compose.yaml`, so you don't set it in `.env`.

**Never put a production `DATABASE_URL` in `.env` expecting it to be
ignored locally.** Rails lets `DATABASE_URL` override `database.yml` for
whatever environment is running, and dotenv loads `.env` for every local
`rails`/`rspec` command — so a prod URL there silently points dev *and
test* at production. `compose.yaml` pins the containers to the local
`postgres` service (`environment` beats `env_file`), but native commands
have no such guard: if `.env` must carry a prod URL for some workflow,
prefix every local command with
`DATABASE_URL=postgresql://localhost/biteworthy_dev` (or `_test`).

## How the apps connect

- **Web → API**: the web app calls `NEXT_PUBLIC_API_BASE` (default
  `http://localhost:3000`). The containerized API publishes `:3000` on the
  host, so the default works whether the API is containerized or native.
- **Mobile → API**: set `EXPO_PUBLIC_API_BASE`. On a simulator
  `http://localhost:3000` works; on a physical device use your machine's
  LAN IP (e.g. `http://192.168.x.y:3000`).

## Ports

| Port | Service |
|---|---|
| `3000` | Rails API (Puma) |
| `3001` | Next.js web dev server |
| `5432` | Postgres (bound to `127.0.0.1`) |
| `8081` | Expo / Metro bundler (when mobile is running) |

## Troubleshooting

- **`bind: address already in use` on 3000/5432** — something is already
  on that port (a native Rails/Postgres, or a previous stack). Stop it, or
  `docker compose down`. The API binds `5432`/`3000` to `127.0.0.1` only.
- **`A server is already running` (stale pid)** — the `api` command clears
  `tmp/pids/server.pid` on boot, but if you crashed mid-run, `docker
  compose restart api` re-runs it.
- **Changed the `Gemfile` and the container can't find a gem** — restart
  (`bundle check` reinstalls) or `docker compose up -d --build` to bake it
  in.
- **Want a clean database** — `docker compose down -v` drops the `pgdata`
  volume; the next `up` recreates and reseeds. Or, without a full reset:
  `docker compose exec api bin/rails db:reset`.
- **Migrations from a teammate's branch** — `docker compose exec api
  bin/rails db:migrate` (or just restart `api`; `db:prepare` runs pending
  migrations on boot).
- **Tests** — run inside the container so they hit the right Postgres:
  `docker compose exec api bundle exec rspec`. CI runs the same suite
  against its own Postgres service (`.github/workflows/ci-api.yml`).
