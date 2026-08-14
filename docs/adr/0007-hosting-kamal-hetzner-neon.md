# ADR 0007: production hosting (Kamal + Hetzner CPX21 + Neon Postgres)

- **Date:** 2026-04-30
- **Status:** Accepted
- **Supersedes:** [ADR 0002](./0002-production-hosting.md) (Fly.io)

## Context

ADR 0002 picked Fly.io and Phase 5.1's PR #172 shipped the wiring (Dockerfile, fly.toml, smoke task, README). Before the live deploy happened, the human elected to reverse the pick — concerns about Fly's ongoing pricing direction + a preference for owning the host rather than leasing per-VM-hour.

This ADR captures the new pick: **Kamal** (Basecamp's container deployer) on **Hetzner CPX21** (one box, two roles), with **Neon** for managed Postgres and **GitHub Container Registry** for the image. ADR 0001's stack-line "Hosting | Fly.io (api)" should be read alongside this — the high-level "self-managed Docker on a VPS" posture is the same intent; the specific provider differs.

## Decision

### Compute — 1 × Hetzner CPX21 in Ashburn

Single box for v1 launch:
- **Hetzner CPX21** — 4 GB RAM, 3 vCPU, 80 GB SSD. **~€8/mo all-in.** (This ADR specified a **CX22** — 2 vCPU / 40 GB / ~€4.5. The CX line is not offered in Hetzner's US datacenters, so provisioning in Ashburn landed on the CPX equivalent: more vCPU and disk, roughly €3/mo more. Verified against `hcloud server describe biteworthy-api` on 2026-08-14.)
- **Datacenter:** `ash-dc1` (Ashburn, Virginia, USA). Nearest Hetzner US datacenter to Durango (~30 ms RTT, dominated by the WAN hop anyway).
- **Both processes on one box:**
  - `web` role — puma serving `:3000`
  - `worker` role — `bundle exec rake solid_queue:start`
  - Same OCI image, different `cmd`. Configured as Kamal **roles** in `config/deploy.yml`.
- **Why same box, not split:** the box has more headroom than the dual-Fly-machine spec it replaces (which was 2 × shared-cpu-1x at 512 MB each = 1 GB total; this box alone is 4 GB). Splitting buys nothing at launch volume + costs an extra €5/mo. Revisit only if puma's RSS + worker's image-decode buffers actually contend.
- **OS:** Ubuntu 24.04 LTS (Hetzner default). Unattended-upgrades configured during `kamal setup` for security patches; major-version upgrades are manual operator events.

### Postgres — Neon (managed, free tier)

- **Neon** — serverless Postgres with branching, auto-suspend on idle. Free tier: 0.5 GB storage + 191.9 compute hours/month. Plenty for Durango beta.
- **Region:** `aws-us-east-1` (matches Hetzner Ashburn's RTT envelope).
- **Connection string:** Neon's **pooled** URL (NOT the unpooled one — puma + worker concurrency would exhaust unpooled connections fast). Sets `DATABASE_URL` via `.kamal/secrets`.
- **Backups:** Neon handles 7-day point-in-time recovery on free tier. We don't need our own `pg_dump` cron.
- **Why managed Postgres, not Postgres-on-the-app-box:**
  - Box rebuilds (kernel upgrades, hardware migrations, mistakes) never risk data.
  - We don't run a backup pipeline ourselves.
  - Neon's branching is genuinely useful for staging (clone prod schema + sample data on demand).
  - Cost difference at our volume is zero (Neon is free until we grow past 0.5 GB or 191 compute-hours).

### Container deploys — Kamal

- **Kamal 2** (`gem install kamal`). Zero-downtime deploys via the bundled `kamal-proxy`. Automatic Let's Encrypt for `api.bite-worthy.com`. Single-command rollback (`kamal rollback`).
- **Migrations on boot.** `db:prepare` runs from `bin/docker-entrypoint` when the `web` role starts. (This ADR originally specified a `.kamal/hooks/pre-deploy` hook as Fly's `[deploy] release_command` analog; it was removed because it ran before any container or env existed, which can't work on a first deploy.) The protection is the same either way: a failed migration exits the container, `/up` never passes, and kamal-proxy holds traffic on the old release.
- **Why Kamal over alternatives:**
  - **vs raw Docker Compose** — Kamal handles the multi-host TLS + zero-downtime cutover for us. Compose would mean writing nginx + certbot + a deploy script.
  - **vs Coolify** (self-hosted PaaS) — Coolify's UX is closer to Render/Heroku, but it's a 3rd-party layer to keep up with. Kamal is just bash + Docker primitives; if Kamal disappears tomorrow, the box still runs the image.
  - **vs Dokku** (older PaaS) — Kamal's multi-host model is more honest; Dokku is single-host by design.

### Image registry — GitHub Container Registry (ghcr.io)

- **Why GHCR** — the source repo (`whiteboard-works/biteworthy`) is on GitHub. Same auth model (PAT with `write:packages`); free for private repos; no separate account.
- **Why not Docker Hub** — image pulls from Docker Hub are rate-limited for unauthenticated requests. Hetzner box without a Docker Hub login would hit the limit during deploy retries.
- **Why not self-hosted (Harbor, etc.)** — operationally not worth it for one image. GHCR is the single piece we don't run ourselves; matches the same posture as Neon for the DB.

### What stays from PR #172 (the Fly.io wiring)

Reused unchanged:
- `apps/api/Dockerfile` — multi-stage Rails 8 production image. Kamal builds the same OCI image Fly would have.
- `apps/api/.dockerignore` — excludes `.env`, `.kamal/secrets` (added by this PR), logs, specs, docs.
- `apps/api/bin/docker-entrypoint` — runs `db:prepare` on the puma process. This ended up being the only place it runs (see above).
- `apps/api/lib/tasks/production.rake` + `app/services/biteworthy/production_smoke.rb` — the smoke runner. URL-driven; works against any host.
- All of Phase 5.2 (SMTP), Phase 5.3 (R2 storage), Phase 5.4 (Vercel for web), Phase 5.5–5.10. Orthogonal.

### What this PR ships (the migration)

- **Delete** `apps/api/fly.toml`.
- **Add** `apps/api/config/deploy.yml` — Kamal config: web + worker roles, GHCR registry, kamal-proxy with `/up` healthcheck + Let's Encrypt for `api.bite-worthy.com`, libjemalloc preload, env-var passthrough.
- **Add** `apps/api/.kamal/secrets.example` — bash-sourceable template for every secret.
- ~~**Add** `apps/api/.kamal/hooks/pre-deploy`~~ — added here, then removed: a pre-deploy hook runs before any container or env exists, so it can never work on a first deploy. `bin/docker-entrypoint` covers it.
- **Update** `apps/api/.gitignore` — exclude `.kamal/secrets`.
- **Update** `apps/api/.env.example` — drop Fly-specific docs, add Kamal/Hetzner/Neon section.
- **Update** `apps/api/README.md` "Production deploy" section — full bootstrap commands inline.
- **Mark** `docs/adr/0002-production-hosting.md` Status as Superseded by this ADR.

### What needs a human (Phase 5.1.1 acceptance criterion)

The acceptance ("`curl https://api.bite-worthy.com/up` returns 200") needs:

1. **Hetzner Cloud account** (https://hetzner.cloud). Generate API token + add ed25519 SSH public key.
2. **Neon account** (https://neon.tech). Create `biteworthy-prod` project in `aws-us-east-1`. Copy the **pooled** connection string.
3. **GitHub PAT** with `write:packages` + `read:packages` scopes.
4. `hcloud server create --name biteworthy-api --type cpx21 --datacenter ash-dc1 --image ubuntu-24.04 --ssh-key skylar`
5. DNS: `api.bite-worthy.com` `A` record at the Hetzner IP.
6. `cp .kamal/secrets.example .kamal/secrets`, fill in real values.
7. Edit `config/deploy.yml`, replace `<REPLACE_WITH_HETZNER_IP>` placeholders.
8. `kamal setup && kamal env push && kamal deploy`.
9. `kamal smoke` (alias for the production smoke task).

Steps 1–3 + 8–9 are the recurring ones; 4–7 are one-time setup.

## Trade-offs

**You own the OS.** Apt updates, kernel reboots, fail2ban, log rotation. Hetzner provides the host; we provide the discipline. Mitigations baked in:
- `unattended-upgrades` configured during `kamal setup` (security patches automatic).
- Hetzner snapshots are €0.012/GB-month + on-demand; daily snapshot of the 40GB disk = €0.50/mo. Worth it.
- Major-version OS upgrades are operator events (not automatic). Document them.

**Single point of failure.** One box; if it dies, mobile + web go dark until we provision a new one. Mitigations:
- Kamal makes provisioning a new box ~10 minutes (`hcloud server create` → `kamal setup` → `kamal deploy`).
- Postgres on Neon means the data survives a box death. The app box is fully reconstitutable from `config/deploy.yml` + `.kamal/secrets`.
- For v1 beta volume (~50–500 daily active users), this is acceptable. Multi-host failover is Phase 6+ if uptime SLAs become a customer ask.

**Vendor lock-in (mild)**:
- **Hetzner** — pricing is famously stable + the lowest in the EU/US VPS market. Migration off Hetzner means provisioning a similar box elsewhere; Kamal config + `.kamal/secrets` carry over unchanged.
- **Neon** — the pooled DATABASE_URL points at a Neon-specific endpoint, but Postgres is Postgres. Migration to AWS RDS / Supabase / self-hosted is a `pg_dump` + `pg_restore` and a config flip.
- **GHCR** — switching to Docker Hub or another registry is a 3-line change in `config/deploy.yml`.
- **Kamal** — local laptop CLI; not bound to any cloud. If Basecamp ever abandons Kamal, the OCI image + the Hetzner box still work; we just lose the deploy automation.

## Consequences

- **Cost** — ~$8/mo (Hetzner CPX21, up from the CX22's ~$5 this ADR projected) + $0 (Neon free tier) + $0 (GHCR for private repo). One-time Hetzner snapshot setup ~$0.50/mo. **Total: ~$6/mo** at launch volume. Compared to Fly's projected $5–15/mo, the floor is similar but the ceiling is dramatically lower as traffic grows (no per-GB-hour billing).
- **Operational discipline** — operator owns OS-level health. Acceptable trade for the cost + control delta. Document a 30-min monthly maintenance window in the launch runbook.
- **Rebuild story** — losing the Hetzner box is recoverable in ~15 min. Losing both the box AND Neon is the catastrophic case (we don't currently snapshot Neon ourselves; revisit if growth warrants).
- **Observability** — Sentry from ADR 0001 still applies; Phase 2.9's cost dashboard at `/admin/dashboard` works regardless of host. PostHog (Phase 5.8) handles funnel analytics.
