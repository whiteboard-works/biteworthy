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
