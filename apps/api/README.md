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

## Production deploy (Phase 5.1.1)

Hosted on **Hetzner CX22** + **Neon Postgres** + **Cloudflare R2**, deployed with **Kamal** (image registry: GitHub Container Registry). Decision + trade-offs in `docs/adr/0007-hosting-kamal-hetzner-neon.md` (which supersedes ADR 0002's Fly.io pick).

**One-time bootstrap (human, ~30 minutes):**

```bash
# 1. Provision the box. Hetzner Cloud Console or hcloud CLI:
hcloud server create \
    --name biteworthy-api \
    --type cx22 \
    --image ubuntu-24.04 \
    --datacenter ash-dc1 \
    --ssh-key skylar
# Note the IP; set the api.bite-worthy.com A record at it.

# 2. Set up Neon (managed Postgres).
#    - Sign up at neon.tech, create a "biteworthy-prod" project in
#      aws-us-east-1.
#    - Copy the POOLED connection string (not the unpooled one —
#      puma + worker concurrency would exhaust unpooled connections).

# 3. Generate a GitHub PAT for ghcr.io access.
#    - Settings → Developer settings → Personal access tokens (classic)
#    - Scopes: write:packages, read:packages

# 4. Fill in the secrets file.
cd apps/api
cp .kamal/secrets.example .kamal/secrets
# Edit .kamal/secrets — put real values for KAMAL_REGISTRY_PASSWORD,
# RAILS_MASTER_KEY, DATABASE_URL (Neon pooled), DEVISE_JWT_SECRET_KEY,
# ANTHROPIC_API_KEY, ADMIN_*, SMTP_*, R2_*. Template's inline notes
# explain where each value comes from.

# 5. Edit config/deploy.yml — replace the two <REPLACE_WITH_HETZNER_IP>
#    placeholders with the IP from step 1.

# 6. First deploy.
gem install kamal
kamal setup            # installs Docker on box, pulls image, boots kamal-proxy
kamal env push          # uploads .kamal/secrets to the box
kamal deploy            # full deploy with db:prepare pre-deploy hook

# 7. Confirm.
kamal smoke             # alias for `app exec "bin/rails biteworthy:production:smoke EXIT_CODE=1"`
curl https://api.bite-worthy.com/up
```

**Every deploy (CI automation deferred to a small follow-up after manual deploys are proven):**

```bash
kamal deploy
kamal smoke             # alias from deploy.yml
```

Useful aliases (all in `config/deploy.yml`):

| `kamal …` | What it runs |
|---|---|
| `console` | `bin/rails console` on the box |
| `shell` | bash on the box |
| `smoke` | the production smoke task with `EXIT_CODE=1` |
| `seed` | the Phase 5.7 Durango batch ingest |
| `logs` | tails Docker logs across all roles |
| `rollback` | reverts to the previous image |

**Where things live (deploy edition):**

| Concern | Path |
|---|---|
| Container image | `Dockerfile` + `.dockerignore` + `bin/docker-entrypoint` |
| Kamal config | `config/deploy.yml` |
| Kamal hooks | `.kamal/hooks/` (`pre-deploy` runs `db:prepare`) |
| Kamal secrets | `.kamal/secrets` (gitignored; template at `.kamal/secrets.example`) |
| Smoke task | `lib/tasks/production.rake` (wraps `app/services/biteworthy/production_smoke.rb`) |
| Production env defaults | `env.clear` block in `config/deploy.yml`; secrets in `.kamal/secrets` |

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

## Blob storage (Phase 5.3)

Production blobs (review photos, dish photos, ingestion menu pages) live on **Cloudflare R2**. Decision + trade-offs in `docs/adr/0004-blob-storage.md` (R2 over S3 because zero egress charges; `aws-sdk-s3` works unchanged because R2 speaks S3). Dev keeps `:local` (disk under `storage/`); test uses in-memory `:test`.

**One-time bootstrap (human):**

```bash
# 1. Cloudflare → R2 → create bucket "biteworthy-blobs", generate
#    an API token with Object Read & Write on the bucket.
fly secrets set \
    R2_ACCESS_KEY_ID=<token-id> \
    R2_SECRET_ACCESS_KEY=<token-secret> \
    R2_BUCKET=biteworthy-blobs \
    R2_ENDPOINT=https://<accountid>.r2.cloudflarestorage.com
fly deploy
```

**(Optional) Migrate any pre-existing blobs to R2:**

```bash
fly ssh console -C 'bin/rails biteworthy:storage:backfill EXIT_CODE=1'
```

The backfill task is **idempotent** — blobs already on the configured service are no-ops, so it's safe to re-run after every deploy or any future service flip (R2 → S3 or back). Logs `[ok] / [skip] / [FAIL]` per blob.
