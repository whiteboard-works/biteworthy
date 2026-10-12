# BiteWorthy Web

Next.js 16 (App Router) + Tailwind, at bite-worthy.com. Dev server on
`:3001`; it expects the Rails API on `:3000`.

## Run it

```bash
pnpm install          # from the repo root
pnpm web dev          # alias for: pnpm --filter @biteworthy/web dev
pnpm web test         # Vitest
pnpm web typecheck && pnpm web lint
```

Copy `.env.example` to `.env.local`. `NEXT_PUBLIC_API_BASE` points at the
API, `NEXT_PUBLIC_POSTHOG_KEY` turns analytics on, and `WEB_PROXY_SECRET`
must match the API's so the server-side proxy routes are trusted.

## What is here

| Area         | Routes                                                                                         | Notes                                                                                                                                                                                                                                                 |
| ------------ | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Public menus | `/restaurants/<country>/<region>/<city>/<slug>`, `/durango`, `/durango/<diet>`                 | Server-rendered, so the city and diet pages are indexable. The diet pages are the organic-search entry point. `/r/<slug>?p=<token>` is the share link the Share button makes; it 301s to the location URL with the token kept.                        |
| Account      | `/signup`, `/login`, `/onboarding`, `/profile`, `/profile/settings`, `/history`, `/u/<handle>` | Avoid lists, strictness, taste signals, saved notes, public bio.                                                                                                                                                                                      |
| Chat         | `/chat`                                                                                        | The assistant: a transcript on the left, a results pane on the right, questions and confirmations the server parks on, photo attachments by button, drag, or paste.                                                                                   |
| Scan         | `/restaurants/<…>/scan`, `/restaurants/new`                                                    | Photo, PDF, or link to a filtered menu without the chat.                                                                                                                                                                                              |
| Admin        | `/admin/…`                                                                                     | The back office: ingestion runs, moderation, restaurants, taxonomy, users. Gated on `is_admin`.                                                                                                                                                       |
| Company      | `/story`, `/press`, `/updates`, `/privacy`, `/terms`, `/dmca`                                  | `/updates` renders `@biteworthy/version-history`.                                                                                                                                                                                                     |
| Proxy        | `/api/…`                                                                                       | Route handlers that forward to the Rails API with the session cookie attached, so the browser never holds a JWT. Every client call in `src/lib/` goes through one of these. A `fetch` to a path with no handler is a 404 the mocked tests cannot see. |

This app **does not filter**. The API sends each item's `status` and
`reasons` and the components render them; `@biteworthy/filter-engine`
supplies the wire types and display helpers (reason chips, section grouping,
Top Picks selection), not a filter.

## Production

Hosted on **Vercel**; decision and trade-offs in
[`docs/adr/0005-web-hosting.md`](../../docs/adr/0005-web-hosting.md).

- Every push to `master` deploys production. Every branch gets a preview at `biteworthy-web-git-<branch>-shadoath42.vercel.app`, which review bots and screenshots use.
- Environment in the Vercel project: `NEXT_PUBLIC_API_BASE=https://api.bite-worthy.com`, `NEXT_PUBLIC_COOKIE_DOMAIN=.bite-worthy.com`, `NEXT_PUBLIC_SITE_URL=https://bite-worthy.com`, `NEXT_PUBLIC_POSTHOG_KEY`, and `WEB_PROXY_SECRET`.
- `NEXT_PUBLIC_COOKIE_DOMAIN` stays **unset** locally (localhost cookies take no domain) and is `.bite-worthy.com` in production; `src/lib/cookie-options.ts` handles both.
- Vercel functions refuse request bodies over 4.5 MB, so photos are shrunk client-side before upload and large uploads go straight to the API on a signed ticket.
- `app/sitemap.ts` and `public/robots.txt` are generated; robots disallows the `/api/*` proxy routes.

Analytics is PostHog, events named only from `@biteworthy/analytics`
([`docs/analytics.md`](../../docs/analytics.md)).
