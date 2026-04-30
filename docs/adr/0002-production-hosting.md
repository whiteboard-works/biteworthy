# ADR 0002: production hosting (Fly.io for the API)

- **Date:** 2026-04-30
- **Status:** **Superseded by [ADR 0007](./0007-hosting-kamal-hetzner-neon.md) (2026-04-30)**
- **Supersedes:** N/A
- **Refines:** ADR 0001 — `Hosting | Fly.io (api) + Vercel (web) + EAS (mobile)`

> **Superseded same day.** The Fly.io pick was reversed at human request before the live deploy ever happened. The wiring shipped in PR #172 (Dockerfile, `bin/docker-entrypoint`, `Biteworthy::ProductionSmoke`, smoke rake task) is reused unchanged by ADR 0007's Kamal+Hetzner+Neon setup. Only `fly.toml` was deleted; everything else carried over. See ADR 0007 for the new decision rationale + what changed.

## Context

ADR 0001 picked Fly.io as the API host at the stack-decision level. Phase 5.1 needs an implementation-level decision: machine model, region, process layout, healthchecks, secret rotation lifecycle. Those choices get baked into `apps/api/fly.toml` + `apps/api/Dockerfile` and rotating any of them means a real migration later, so they deserve a dedicated record.

The alternatives considered now (Render, Railway) were also considered in ADR 0001; this ADR reaffirms the Fly.io pick against Phase 5's actual requirements rather than re-litigating it from scratch.

## Decision

### Machine model — Fly Machines (not Apps v1)

Fly's "Machines" platform replaces the older "Apps v1" model. Differences that matter for BiteWorthy:

- **Per-process VM specs**: `app` (puma) and `worker` (`solid_queue:start`) get separate `[[vm]]` blocks. Puma can scale to zero between requests; the worker stays warm so queued ingestion jobs run promptly.
- **Auto-stop / auto-start**: `auto_stop_machines = "stop"` + `min_machines_running = 1` keeps one puma VM alive for `/up` healthchecks; additional VMs spin up on demand. At Durango-launch volume this should stay at 1 machine ~95% of the day.
- **Release commands run as a one-off Machine**: `release_command = "./bin/rails db:prepare"` runs in its own VM, not in the puma process — schema migrations don't block the rolling deploy.

### Region — DEN (Denver)

Closest Fly region to Durango (~6h drive). Single-digit-ms RTT for the launch market matters less than for a global product, but it's free to pick the right one upfront. Add fra/syd later only if real traffic from Europe/AU materializes.

### Process model — two processes, one image

```
[processes]
  app    = "./bin/rails server"
  worker = "bundle exec rake solid_queue:start"
```

Same Dockerfile, same gemset, different command. Wrong shape (`SOLID_QUEUE_IN_PUMA=true` to embed jobs in puma) was rejected because:

- Puma `auto_stop` would kill in-flight ingestion jobs.
- Puma RSS would balloon to fit the worst-case ingestion job's image-decode buffer.
- Independent scaling of puma vs worker is a near-certain Phase 6 need.

### Postgres — Fly Postgres dev tier to start

`fly postgres create --vm-size shared-cpu-1x` provisions a single-VM unmanaged Postgres. Switch to a real plan (e.g. Supabase or Crunchy Bridge) when:

1. Daily backups become a compliance requirement, OR
2. The Phase 5.7 seed run reveals connection-pool pressure, OR
3. Restore-time SLAs become a thing.

Fly Postgres dev is fine for a launch beta. Connection string flows in via `fly postgres attach` (sets `DATABASE_URL` automatically).

### Secret rotation lifecycle

Production secrets live in `fly secrets`:

- **Bootstrap**: `fly secrets set RAILS_MASTER_KEY=... ANTHROPIC_API_KEY=... DEVISE_JWT_SECRET_KEY=... ADMIN_USERNAME=... ADMIN_PASSWORD=...` once.
- **Rotation**: re-run `fly secrets set` for the changed key; Fly performs a rolling restart automatically.
- **Audit**: `fly secrets list` shows hashes only (Fly never echoes values back). Real audit relies on the source-of-truth (1Password vault or similar — human-managed).

`config/master.key` itself stays out of git (`.gitignore`); only the encrypted `config/credentials.yml.enc` is checked in.

### Healthcheck — `/up` (Rails default)

Rails 8's `rails/health#show` mounted at `/up` returns 200 when the app boots without raising. fly.toml polls every 30s with a 10s grace period on boot.

### Image build — multi-stage Dockerfile, not buildpacks

Hand-rolled multi-stage Dockerfile (see `apps/api/Dockerfile`) over Fly's auto-detect. Reasons:

- Phase 4.11.1's `imagemagick` runtime dep + Phase 5.3's planned `libvips` need explicit OS-package install — buildpacks would miss them.
- Multi-stage gives ~150MB smaller images vs the buildpack default (matters for cold-boot times on auto-stopped machines).
- Bootsnap precompile is the single biggest cold-boot speedup; needs explicit `bundle exec bootsnap precompile` in the build stage.

### What this PR ships

- `apps/api/Dockerfile` + `.dockerignore` + `bin/docker-entrypoint`
- `apps/api/fly.toml` with the process / vm / healthcheck config above
- `apps/api/lib/tasks/production.rake` + `app/services/biteworthy/production_smoke.rb` for post-deploy smoke
- `apps/api/.env.example` updated with Fly-specific env vars
- This ADR

### What requires a human (Phase 5.1 acceptance criterion)

The acceptance criterion (`curl https://api.bite-worthy.com/up` returns 200) needs:

1. `fly auth login` with a personal Fly account.
2. `fly launch --no-deploy --copy-config --name biteworthy-api` to register the app.
3. `fly postgres create --name biteworthy-pg --region den` + `fly postgres attach biteworthy-pg`.
4. `fly secrets set ...` for the secrets enumerated above.
5. `fly deploy`.
6. DNS: `api.bite-worthy.com` CNAME to `biteworthy-api.fly.dev`, then `fly certs add api.bite-worthy.com`.
7. `bin/rails biteworthy:production:smoke HOST=https://api.bite-worthy.com` to confirm.

Steps 1–3 + 7 are one-time bootstrap; 4 happens whenever a secret rotates; 5 happens on every merge to master once Phase 5.4 wires CI to drive `fly deploy`.

## Trade-offs

**Why not Render** — Render's free tier doesn't include background workers; the paid tier (~$7/mo per service × 2 services + DB) is more than Fly's equivalent. Render's git-driven deploys are nicer than Fly's CLI-driven model, but Phase 5.4 closes that gap with CI.

**Why not Railway** — comparable pricing, but the worker-process abstraction is less mature than Fly's `[[vm]]` block. Railway is on the shortlist if Fly's billing surprises us.

**Why not Heroku** — pricing per dyno is now meaningfully higher than Fly Machines for the same RAM. Add-on ecosystem advantage is moot since we're using Solid Queue (no Redis) + Fly Postgres.

**Why not raw EC2 / Hetzner / etc.** — operational overhead (TLS termination, healthchecks, log aggregation, secret store, deploy automation) rivals the per-month cost difference. Phase 5 is about shipping; reaching for IaaS is for Phase 6+ if Fly's bill ever bites.

## Consequences

- **Cost** — projected $5–15/mo for the API + worker + Postgres dev tier at launch volume. Tier up after the Phase 5.7 seed run reveals real load.
- **Vendor lock-in** — fly.toml is Fly-specific but small (~50 lines); a Render / Railway migration would be a 1-day port. The Dockerfile is portable as-is.
- **Single region** — all data lives in DEN. Adding a read replica or fail-over plan is Phase 6+ work; we accept the single point of failure at launch.
- **Secret-rotation discipline** — Fly secrets show only hashes; the loop CANNOT verify a secret value, only its presence. Rotation events live in human-kept logs (1Password audit trail).
