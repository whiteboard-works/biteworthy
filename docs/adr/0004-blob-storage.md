# ADR 0004: production blob storage (Cloudflare R2)

- **Date:** 2026-04-30
- **Status:** Accepted
- **Refines:** ADR 0001 (the stack pick named "ActiveStorage → S3 / R2" but didn't pick which)

## Context

Phases 2.3, 4.3, and 4.11.3 all attach blobs via ActiveStorage:
- Phase 2.3 — `IngestionRun.has_many_attached :inputs` (uploaded menu pages, kept around for the ingestion lifetime + audit trail).
- Phase 4.3 — `Review.has_one_attached :photo` (review photos, kept forever).
- Phase 4.11.3 — `Item.has_one_attached :photo` (cropped dish photos, kept forever).

All three deferred the production storage choice to "Phase 5+ when we're actually launching." This is that decision.

The launch volume:
- Review photos at ~1MB average, ~50–500/month → 0.5–5 GB/year.
- Dish photos at ~100KB average (cropped JPEGs from menu pages), ~1k/month after seed → 0.1–1 GB/year.
- Ingestion inputs at ~3MB average (full menu page photos), ~100/month → 4 GB/year, but with a TTL (delete after 90 days).

Total: 5–10 GB/year + heavy READ traffic on review + dish photos (every restaurant page render fans out).

## Decision

**Cloudflare R2** for production. Use the existing `aws-sdk-s3` gem unchanged — R2 speaks the S3 API, so the only delta from `:amazon` is endpoint + region + `force_path_style: true`.

### Why R2 over S3

Read traffic dominates the bill on a photo-heavy product. AWS S3 charges $0.09/GB egress (after the first 100 GB free tier) — at ~10k restaurant page views/month with ~5 dish photos averaging 100KB each, that's ~5 GB/month, or ~$45/month at scale just for serving images. **R2 charges $0 egress.** Period.

| Provider | Storage | Egress | Op cost (per million GET) |
|---|---|---|---|
| **Cloudflare R2** | $0.015/GB-month | **$0** | $0.36 |
| AWS S3 (Standard) | $0.023/GB-month | $0.09/GB | $0.40 |
| Backblaze B2 | $0.005/GB-month | $0.01/GB | $0.40 |
| Wasabi | $0.0069/GB-month | $0 (with caps) | included |

R2 wins on the metric that scales with our traffic. Backblaze + Wasabi are cheaper on storage but worse on operational maturity (Wasabi's "free egress" has fine-print caps; Backblaze has a smaller global edge footprint). AWS S3 is the most mature but the egress cost is real money at scale.

### Why use `aws-sdk-s3` instead of an R2-native gem

R2 implements the S3 API. ActiveStorage's `service: S3` adapter works against R2 with three extra config keys:

```yaml
r2:
  service: S3
  endpoint: <%= ENV["R2_ENDPOINT"] %>
  region: <%= ENV.fetch("R2_REGION", "auto") %>
  force_path_style: true
```

That's it. No new gem, no new wire format, no new test infra. If R2 ever goes down or pricing changes, flip back to `:amazon` with a one-line `production.rb` change — both services share `aws-sdk-s3` so blobs already uploaded to R2 are accessible from any S3-compatible client.

### What this PR ships

- `apps/api/config/storage.yml` — new `:r2` block (S3 service with R2 endpoint).
- `apps/api/config/environments/production.rb` — `active_storage.service = :r2` (was `:amazon`). The `:amazon` block stays in `storage.yml` as a no-code-change fallback.
- `apps/api/.env.example` — adds `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_BUCKET`, `R2_REGION` (defaults to `auto`).
- `apps/api/app/services/biteworthy/storage_backfill.rb` + `lib/tasks/storage.rake` — idempotent migration that re-uploads any blob whose `service_name` doesn't match the configured service. Logs `[ok] / [skip] / [FAIL]` per blob; exits non-zero with `EXIT_CODE=1` on any failure for CI.
- 4 specs guarding the runner.
- `apps/api/README.md` — new "Storage" section documenting the bootstrap + the migration command.
- This ADR.

### What still needs a human (Phase 5.3 acceptance criterion)

The acceptance ("a review photo posted in production survives a server restart and renders on the web restaurant page") needs:

1. Create a Cloudflare account + an R2 bucket named `biteworthy-blobs` (or your preferred name). Enable public access if you want CDN-served URLs without ActiveStorage's signed-redirect; otherwise leave private and rely on Rails-routed URLs (`rails_blob_url`).
2. Generate an R2 API token with read/write to the bucket. Note the **endpoint** URL Cloudflare gives (typically `https://<accountid>.r2.cloudflarestorage.com`).
3. ```bash
   fly secrets set \
       R2_ACCESS_KEY_ID=<token-id> \
       R2_SECRET_ACCESS_KEY=<token-secret> \
       R2_BUCKET=biteworthy-blobs \
       R2_ENDPOINT=https://<accountid>.r2.cloudflarestorage.com
   ```
4. `fly deploy`.
5. Optional CORS — required only if the Phase 5.4 web app starts uploading directly to R2 via signed URLs. ActiveStorage's redirect flow (Rails serves `rails_blob_url`, 302s to the R2 signed URL) doesn't need CORS.
6. (Pre-existing blobs only) `fly ssh console -C 'bin/rails biteworthy:storage:backfill EXIT_CODE=1'` once the secrets are set, to migrate any old `:local` or `:amazon` blobs to R2.

### Direct CDN serving (deferred)

ActiveStorage today serves blobs via `rails_blob_url`, which 302s to a signed R2 URL. This works but adds one round-trip per image and burns puma's request handlers on what should be edge-cached static. For Phase 5+ we can:

1. Make the R2 bucket public, OR
2. Front R2 with a Cloudflare Worker that handles auth + caching.

Either is non-blocking for v1 launch. The redirect overhead (~40ms) is invisible at Durango-beta volume.

## Trade-offs

**Vendor lock-in (mild)** — R2's API is S3-compatible but Cloudflare's specific value prop (zero egress) is unique to them. Migrating off R2 means paying egress somewhere else. Acceptable: they're the cheapest choice for the launch, and migration is a one-line config change.

**No multi-region replication** — R2 has multi-region buckets in beta but they cost more. Single-region is the right launch posture; revisit if Durango-beta traffic justifies it.

**Public-read posture deferred** — keeping the bucket private + signed-redirect serving is the most conservative choice. Phase 5.5 / 5.6 might want public CDN URLs for the og:image generator — call it out then.

## Consequences

- **Cost** — projected $1–3/month at launch volume; scales linearly with storage but not with traffic.
- **Operational** — one provider for blobs (separate from the API host on Fly.io). Cloudflare account is a new place to look when something's wrong; document credentials in 1Password alongside Fly + Postmark.
- **Test infra** — unchanged. The `:test` ActiveStorage service (in-memory) keeps specs fast and offline.
- **Migration** — `bin/rails biteworthy:storage:backfill` is reusable for any future service flip (R2 → S3, or back), not just this one launch event.
