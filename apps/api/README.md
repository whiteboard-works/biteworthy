# BiteWorthy API

Rails 8 JSON API on Postgres 16, at `apps/api/` in the monorepo. It is not
part of the pnpm workspace; it has its own Bundler tree. It owns the filter,
the chat loop, the MCP server, menu ingestion, and everything the web and
mobile apps read.

## Run it

The quickest path is the containerized stack from the repo root
(`docker compose up` boots the API, its worker, and Postgres). Natively:

```bash
docker compose up -d postgres   # from the repo root, or any local Postgres 16
cd apps/api
bundle install
bin/rails db:prepare            # create + load schema + seed, idempotent
bin/rails s -p 3000             # the web app expects the API here
bin/jobs                        # Solid Queue worker, in a second terminal
```

Or boot the worker inside Puma with `SOLID_QUEUE_IN_PUMA=true bin/rails s`.
Postgres needs the `ltree`, `pg_trgm`, `pgcrypto`, and `citext` extensions;
the migrations enable them, so the role needs `CREATE EXTENSION` once.
Dish-photo cropping shells out to ImageMagick and oversized menu PDFs to
Ghostscript; without `gs` such a PDF is refused rather than shrunk.

Copy `.env.example` to `.env` for the optional keys. Only ingestion and the
chat need `ANTHROPIC_API_KEY`.

## Check it

```bash
bundle exec rspec                               # the suite (~3,000 examples)
bundle exec rspec spec/requests/foo_spec.rb:42  # one example
bundle exec rubocop --parallel                  # blocks in CI; new code must be clean
bundle exec brakeman --no-pager --quiet         # blocks in CI
```

Specs that talk to Anthropic replay VCR cassettes from `spec/cassettes/`; CI
runs with `record: :none`, so a new model call needs a committed cassette.

## What it serves

| Path        | What                                                                                                                                                                                                                |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/api/v1/…` | Everything the apps use: auth, profiles, restaurants and items with the filter applied, reviews, photos, scans, the chat (`/conversations`), admin.                                                                 |
| `/mcp`      | The MCP server. The same tool catalogue the chat uses, for any MCP client, with OAuth discovery under `/.well-known/` and dynamic client registration at `/oauth/register`. See [`docs/mcp.md`](../../docs/mcp.md). |
| `/api-docs` | The OpenAPI document, rendered by rswag.                                                                                                                                                                            |
| `/up`       | Health check, used by the deploy's cutover.                                                                                                                                                                         |

The OpenAPI document is built from the rswag specs in `spec/integration/`.
`bin/openapi-export` writes it to `docs/openapi.json`, and
`pnpm --filter @biteworthy/api-types build:codegen` turns it into TypeScript.
Run both after any endpoint change; CI fails on drift.

## Where things live

| Concern                                                      | Path                                                                       |
| ------------------------------------------------------------ | -------------------------------------------------------------------------- |
| The filter (the only place a dish becomes visible or hidden) | `app/services/menus/` (`Menus::Filter`, `Menus::Query`)                    |
| Taste ranking                                                | `app/services/taste_scoring.rb`                                            |
| The chat loop, prompt, compaction, grounding review          | `app/services/chat/` (`Chat::AgentLoop` is the heart)                      |
| Tools: one catalogue for the chat and MCP, grouped by domain | `app/services/tools/` ([`docs/mcp.md`](../../docs/mcp.md))                 |
| Menu ingestion: photo or PDF to staged items                 | `app/services/ingestion/` ([`docs/ingestion.md`](../../docs/ingestion.md)) |
| Anthropic client, TypeSafe (Jev) client                      | `app/services/anthropic_client.rb`, `app/services/typesafe_client.rb`      |
| Restaurants, cities, dish photos, images, PDFs               | `app/services/{restaurants,cities,dish_photos,images,pdfs}/`               |
| Error reports to GitHub issues                               | `app/services/error_reports/`                                              |
| Controllers                                                  | `app/controllers/api/v1/`, `app/controllers/mcp_controller.rb`             |
| Background jobs                                              | `app/jobs/` (Solid Queue, in the same Postgres)                            |
| Migrations                                                   | `db/migrate/` (never edit a shipped one; add a new one)                    |
| Seed taxonomy                                                | `db/seeds/{tags,ingredients,dietary_profiles}.yml`                         |
| Production tasks (smoke, seed, backfills)                    | `lib/tasks/`                                                               |

The data model is toured in [`docs/schema.md`](../../docs/schema.md).

## Production

Hosted on a **Hetzner** box with **Neon** Postgres and **Cloudflare R2** for
blobs, deployed with **Kamal** from an image on GitHub Container Registry.
The decision and its trade-offs are in
[`docs/adr/0007-hosting-kamal-hetzner-neon.md`](../../docs/adr/0007-hosting-kamal-hetzner-neon.md).

**Every deploy is automatic.** `.github/workflows/deploy-api.yml` runs
`kamal deploy` on a merge to `master` that touches `apps/api/`. The entrypoint
runs `db:prepare` on boot, so migrations ride along, and kamal-proxy keeps
traffic on the old release until `/up` passes. The workflow logs into the
registry with its own `GITHUB_TOKEN`; the PAT in `.kamal/secrets` is only for
deploys from a laptop. Re-run a failed deploy from the Actions tab, or:

```bash
gh run rerun <run-id> --failed
```

From a laptop, with `.kamal/secrets` filled in from `.kamal/secrets.example`:

```bash
kamal deploy
kamal smoke              # bin/rails biteworthy:production:smoke, fails loudly
kamal console            # a Rails console on the box
kamal shell              # bash on the box
kamal app logs           # Docker logs; they do not outlive a deploy
kamal rollback <version> # back to a previous image
```

Secrets live in two places that must agree: `.kamal/secrets` on the laptop
and the `KAMAL_SECRETS_B64` repo secret the workflow decodes. After changing
any value, run `bin/kamal-secrets-push` (add `--deploy` to ship), or the next
CI deploy reverts it.

| Concern                  | Path                                                                |
| ------------------------ | ------------------------------------------------------------------- |
| Image                    | `Dockerfile`, `.dockerignore`, `bin/docker-entrypoint`              |
| Kamal config and aliases | `config/deploy.yml`                                                 |
| Secrets                  | `.kamal/secrets` (gitignored; template at `.kamal/secrets.example`) |
| Smoke task               | `lib/tasks/production.rake`                                         |

### One-time provisioning

Already done for production; kept for a rebuild or a second environment.
The full checklist with every credential is
[`docs/launch-readiness.md`](../../docs/launch-readiness.md).

- **Box:** `hcloud server create --name biteworthy-api --type cpx21 --image ubuntu-24.04 --datacenter ash-dc1`, then point `api.bite-worthy.com` at it and run `kamal setup`.
- **Database:** a Neon project; use the _pooled_ connection string, since Puma plus the worker would exhaust an unpooled one.
- **Email:** Resend, sending domain `mail.bite-worthy.com` with DKIM and SPF published; the API key goes in `SMTP_PASSWORD`. Plain SMTP, no provider gem ([`docs/adr/0003-email-provider.md`](../../docs/adr/0003-email-provider.md); that ADR's Postmark pick was swapped for Resend). Confirm with `kamal app exec --roles web 'bin/rails biteworthy:email:smoke EMAIL=you@example.com'`.
- **Blobs:** an R2 bucket `biteworthy-blobs` and a token with object read and write; the `R2_*` values go in the secrets. `aws-sdk-s3` works unchanged because R2 speaks S3 ([`docs/adr/0004-blob-storage.md`](../../docs/adr/0004-blob-storage.md)). `bin/rails biteworthy:storage:backfill` moves any blobs stored elsewhere and is idempotent.
- **Registry:** the `biteworthy-api` package on GHCR must grant this repository write access under _Manage Actions access_, or the workflow's token logs in but cannot push.
