# BiteWorthy API

Rails 8 JSON API. Lives at `apps/api/` inside the monorepo.

## Local setup

```bash
cd apps/api
bundle install
bin/rails db:create db:schema:load db:seed
bin/rails s -p 3000
```

Postgres 16+ with `ltree`, `pg_trgm`, `pgcrypto`, and `citext` extensions.
The migrations enable them automatically (your role needs `CREATE EXTENSION`
privilege the first time).

## Routes

All app traffic lives under `/api/v1`. `/up` is the health check.
`/api-docs` renders the OpenAPI spec via rswag (Phase 1 work-in-progress).

## Background jobs

Solid Queue runs in the same Postgres database as the app. Boot it inline
with `SOLID_QUEUE_IN_PUMA=true bin/rails s` or as its own process with
`bin/jobs`.

## Tests

```bash
bundle exec rspec
```

## Where things live

| Concern | Path |
|---|---|
| Migrations | `db/migrate/` |
| Seed taxonomy (YAML) | `db/seeds/{tags,ingredients,dietary_profiles}.yml` |
| Models | `app/models/` |
| API controllers | `app/controllers/api/v1/` |
| Ingestion services (Anthropic) | `app/services/ingestion/` |
| Background jobs | `app/jobs/` |

## Production deploy (Phase 5.1)

Hosted on Fly.io. Decision + trade-offs in `docs/adr/0002-production-hosting.md`.

**One-time bootstrap (human):**

```bash
cd apps/api
fly auth login
fly launch --no-deploy --copy-config --name biteworthy-api
fly postgres create --name biteworthy-pg --region den --vm-size shared-cpu-1x
fly postgres attach biteworthy-pg
fly secrets set \
    RAILS_MASTER_KEY=$(cat config/master.key) \
    DEVISE_JWT_SECRET_KEY=$(bin/rails secret) \
    ANTHROPIC_API_KEY=... \
    ADMIN_USERNAME=... ADMIN_PASSWORD=...
fly deploy
fly certs add api.bite-worthy.com   # after CNAME points at biteworthy-api.fly.dev
```

**Every deploy (automated post-Phase-5.4 CI; today: manual):**

```bash
fly deploy
bin/rails biteworthy:production:smoke HOST=https://api.bite-worthy.com EXIT_CODE=1
```

The smoke task is read-only — safe to run repeatedly. It hits `/up` plus a real items query and prints one timing line per check; exits non-zero when `EXIT_CODE=1` is set so CI can fail the deploy if the smoke fails.

**Where things live (deploy edition):**

| Concern | Path |
|---|---|
| Container image | `Dockerfile` + `.dockerignore` + `bin/docker-entrypoint` |
| Fly app config | `fly.toml` |
| Smoke task | `lib/tasks/production.rake` (wraps `app/services/biteworthy/production_smoke.rb`) |
| Production env defaults | `[env]` block in `fly.toml`; secrets via `fly secrets` |

## Email (Phase 5.2)

Production SMTP is wired in `config/environments/production.rb`. Decision + trade-offs in `docs/adr/0003-email-provider.md` (Postmark via plain SMTP). Dev + test use the `:test` adapter — no real delivery — so specs don't open sockets.

**One-time bootstrap (human):** sign up for Postmark, create a "BiteWorthy" server, verify the `bite-worthy.com` sender domain (DKIM + Return-Path DNS records), generate a Server API token, then:

```bash
fly secrets set \
    SMTP_ADDRESS=smtp.postmarkapp.com \
    SMTP_PORT=587 \
    SMTP_USERNAME=$POSTMARK_TOKEN \
    SMTP_PASSWORD=$POSTMARK_TOKEN \
    SMTP_DOMAIN=bite-worthy.com \
    MAILER_HOST=https://bite-worthy.com
```

**Confirm delivery:**

```bash
fly ssh console -C 'bin/rails biteworthy:email:smoke EMAIL=you@example.com'
```

Reports the SMTP Message-ID per delivery; `EXIT_CODE=1` makes it fail loudly for CI.

**What works after secrets are set** — Devise password reset (built-in), `RestaurantClaimMailer.verify_email` (Phase 4.9), and any new mailer added later. No code change needed per mailer.
