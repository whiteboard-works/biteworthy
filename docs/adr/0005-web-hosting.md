# ADR 0005: production web hosting (Vercel)

- **Date:** 2026-04-30
- **Status:** Accepted
- **Refines:** ADR 0001 (the stack pick named `Vercel (web)` but didn't pick the deploy details)

## Context

Phase 5.4 needs a production home for `apps/web` (Next.js 15 App Router). ADR 0001 already named Vercel; this ADR captures the implementation-level details that the loop's deploy depends on, plus the cookie-domain decision that affects how the JWT session works at launch.

## Decision

### Vercel — confirmed

Free tier (Hobby) covers a Durango-scale launch beta:

- 100 GB bandwidth/month — easily covers 10k page views with image-heavy SSR.
- Unlimited static asset serving from Vercel's CDN.
- Native Next.js 15 App Router support — no Dockerfile needed; auto-detects framework, server functions, image optimization.
- Free SSL + automatic HTTPS for custom domains.
- Preview deploys per PR with no extra setup.

Cloudflare Pages was the alternative considered. It's cheaper at scale and handles edge functions well, but:

- Next.js App Router on CF Pages requires `@cloudflare/next-on-pages` adapter — extra build step + occasional behavioral drift from Vercel's reference Next runtime.
- Vercel is the reference platform for Next; bugs we hit are likelier to be addressed upstream.
- Free-tier limits are comparable for our launch volume.

Revisit Cloudflare Pages in Phase 6+ if Vercel pricing ever bites or if we need fine-grained edge logic (e.g. per-region SEO).

### Deploy lifecycle

- **Push to a feature branch** → Vercel auto-deploys a preview at `<branch>--biteworthy.vercel.app`. Useful for codex review of UX changes.
- **Merge to master** → Vercel auto-deploys to production at `bite-worthy.com`.
- **No CI changes needed** — Vercel polls GitHub. Phase 5.4's CI keeps running typecheck/lint/test in GitHub Actions; Vercel builds in parallel.

### Region — `iad1` (Washington DC)

Vercel functions run in a region. `iad1` is the eastern-US default and the closest free-tier option to Durango. Latency for SSR-heavy routes (restaurant pages, the future `/durango/[diet]` pages) lives or dies on the round-trip to the API at Fly's `den` region — `iad1` → `den` is ~30ms, which dominates everything else and is fine for v1.

Multi-region SSR is paid-tier. Revisit when the funnel justifies it.

### Cookie domain — `.bite-worthy.com`

The Phase 4.1 auth cookie is currently set without a `domain` attribute (browser scopes it to the origin). For production we set `NEXT_PUBLIC_COOKIE_DOMAIN=.bite-worthy.com` so the cookie works across:

- `bite-worthy.com` (apex — marketing landing, Phase 5.5)
- `www.bite-worthy.com` (canonical)
- `app.bite-worthy.com` (potential future subdomain for the React app, deferred Phase 6+)

Dev / CI leave the env var unset because **localhost cookies must NOT carry a domain attribute** — the browser silently drops them otherwise. The `buildAuthCookieOptions` helper in `apps/web/src/lib/cookie-options.ts` enforces this.

### What this PR ships

- `apps/web/vercel.json` — minimal config: framework hint, region pin, security response headers.
- `apps/web/public/robots.txt` — allow-everything except `/api/` proxy routes.
- `apps/web/src/app/sitemap.ts` + `apps/web/src/lib/sitemap.ts` — Next 13+ sitemap generator with hooks for Phase 5.6 diet pages + Phase 5.7 seeded restaurants. Pure-TS helper is unit-tested without touching Next.
- `apps/web/src/lib/cookie-options.ts` — extracted auth-cookie attribute builder; reads `NEXT_PUBLIC_COOKIE_DOMAIN`. The `app/api/auth/[action]/route.ts` proxy now goes through it (3-line refactor).
- `apps/web/.env.example` — first one for the web app; documents `NEXT_PUBLIC_API_BASE` + `NEXT_PUBLIC_COOKIE_DOMAIN`.
- `apps/web/README.md` — adds Production deploy section.
- This ADR.

10 new vitest cases (5 sitemap + 5 cookie-options).

### What still needs a human (Phase 5.4 acceptance criterion)

The acceptance ("`https://bite-worthy.com` resolves to the marketing landing and the SSR restaurant pages work") needs:

1. Sign up for Vercel (free Hobby tier).
2. Import the GitHub repo. Vercel auto-detects the Next.js app at `apps/web`.
3. Set environment variables in the Vercel project settings:
   - `NEXT_PUBLIC_API_BASE=https://api.bite-worthy.com`
   - `NEXT_PUBLIC_COOKIE_DOMAIN=.bite-worthy.com`
   - `NEXT_PUBLIC_SITE_URL=https://bite-worthy.com` (controls sitemap base URL; defaults to that string but explicit is better in env-var land).
4. Add `bite-worthy.com` + `www.bite-worthy.com` as custom domains in the Vercel project. Vercel emits the DNS records to add at the registrar (apex `A` record + `www` `CNAME`).
5. (Optional) `vercel link` from `apps/web/` if a human wants to use the CLI for one-off `vercel logs` or `vercel env pull`.

Steps 1–2 + 4 are one-time bootstrap; 3 happens on env-var rotation.

## Trade-offs

**Vendor lock-in (mild)** — `vercel.json` is Vercel-specific but tiny (~15 lines); migrating to CF Pages or self-hosted Next is a one-day port. The Next.js code has no Vercel-runtime calls.

**No edge functions in v1** — Vercel's serverless runtime is fine for v1's traffic. Edge would help global TTFB but Durango-only launch doesn't justify the complexity.

**Single region** — accepts a 30ms penalty for non-eastern-US visitors. Multi-region is paid + Phase 6+.

## Consequences

- **Cost** — free at launch volume. First paid tier ($20/mo) kicks in at >100 GB bandwidth, which we won't hit pre-organic-growth.
- **Operational** — three places to look when something breaks: Vercel (web), Fly (api), Cloudflare R2 (blobs). Document credentials side-by-side in 1Password.
- **Cookie-domain semantics** — the `NEXT_PUBLIC_COOKIE_DOMAIN` indirection lets dev work without breaking prod. Future subdomain additions (e.g. `app.bite-worthy.com`) inherit the cookie automatically.
