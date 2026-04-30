# BiteWorthy Web

Next.js 15 (App Router) + Tailwind. Dev server on `:3001`; the Rails API
runs on `:3000`.

## Local

```bash
pnpm install         # from repo root
pnpm web dev         # alias for: pnpm --filter @biteworthy/web dev
```

Set `NEXT_PUBLIC_API_BASE` to override the Rails URL.

## Why Next + Tailwind

- SEO matters: city-scoped filter pages (`/durango/gluten-free`) are
  organic-discovery gold. SSR delivers them rendered.
- Real-time filter UX (toggle "no dairy" → list updates) is built around
  client components hydrating SSR'd lists.
- Tailwind tokens come from `@biteworthy/ui-tokens` so the mobile app's
  StyleSheet and the web's classes stay in lockstep.

## Production deploy (Phase 5.4)

Hosted on Vercel. Decision + trade-offs in `docs/adr/0005-web-hosting.md`.

**One-time bootstrap (human):**

1. Sign up for Vercel (Hobby tier is free).
2. Import the GitHub repo via the Vercel dashboard — Vercel auto-detects the Next.js app at `apps/web`.
3. Set environment variables in the project's Settings → Environment Variables:
   - `NEXT_PUBLIC_API_BASE=https://api.bite-worthy.com`
   - `NEXT_PUBLIC_COOKIE_DOMAIN=.bite-worthy.com` (cookie scoped across subdomains)
   - `NEXT_PUBLIC_SITE_URL=https://bite-worthy.com` (sitemap base URL)
4. Add `bite-worthy.com` + `www.bite-worthy.com` as custom domains. Vercel emits the DNS records to add at the registrar.

**Every deploy:** push to `master` → Vercel auto-deploys to production. Push to a feature branch → Vercel emits a preview URL (`<branch>--biteworthy.vercel.app`) which is useful for codex review of UX changes.

**Sitemap + robots:** generated automatically. `app/sitemap.ts` covers `/`, `/login`, `/signup` today; Phase 5.6 adds `/durango/[diet]` rows; Phase 5.7 adds seeded-restaurant rows. `public/robots.txt` allows all bots and disallows the `/api/*` server-side proxy routes.

**Cookie domain (Phase 5.4):** `NEXT_PUBLIC_COOKIE_DOMAIN` must be UNSET locally (localhost cookies don't take a domain attribute) and SET to `.bite-worthy.com` in Vercel production. The `buildAuthCookieOptions` helper in `src/lib/cookie-options.ts` honors both.
