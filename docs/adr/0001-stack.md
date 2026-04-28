# ADR 0001: v2 stack

- **Date:** 2026-04-28
- **Status:** Accepted
- **Supersedes:** the implicit 2020 stack archived in `_legacy/`

## Context

BiteWorthy v1 (Rails 4.2.11 / Ruby 2.5.7) shipped in 2018-2020 and went
dormant after Heroku free dynos retired in 2022. Reviving it requires
choosing between an in-place upgrade chain (4.2 → 5 → 6 → 7 → 8 across
nine years of deprecations, plus replacing Paperclip, Foundation 6, jQuery,
CoffeeScript, ES 6, Devise patterns, asset pipeline...) and a clean rewrite
that reuses the data-model insight but starts from current defaults.

The product also pivots: v1 was a hand-curated menu wiki with 14 user
levels gamifying contributions. v2 is an AI-assisted dietary filter
("scan any menu, see only what you can eat") where ingestion is automated
and the filter is the headline feature.

## Decision

Clean rewrite in a monorepo. Stack:

| Layer | Pick | Notes |
|---|---|---|
| API | Rails 8 + Ruby 3.3.6 | Solid Queue / Cache / Cable run on Postgres — no Redis. |
| DB | Postgres 16 | `ltree` for taxonomy, `pg_trgm` for fuzzy match, GIN arrays for filter. |
| Search | Postgres FTS + pg_trgm | Drops Elasticsearch entirely. |
| Storage | ActiveStorage → S3 / R2 | Replaces Paperclip. |
| Auth | Devise + devise-jwt + OmniAuth | Apple (App Store requirement), Google, email. |
| Background | Solid Queue | Same Postgres as the app. |
| Web | Next.js 15 App Router + Tailwind | SSR for SEO city-filter pages. |
| Mobile | Expo SDK 52 + React Native | Camera / OAuth / OTA built in. Same TS as web. |
| State | TanStack Query + Zustand | Server vs UI state separation. |
| AI | Claude Sonnet 4.6 (vision + structured outputs) | Prompt-cached taxonomy. |
| Hosting | Fly.io (api) + Vercel (web) + EAS (mobile) | Cheap, app-shaped. |
| CI | GitHub Actions | Two jobs: `js` (web/mobile/packages) and `api` (Rails). |
| Errors | Sentry | One project, three DSNs. |

### Repo layout

```
apps/api      Rails 8 JSON API
apps/web      Next.js 15
apps/mobile   Expo
packages/api-types       hand-written for now, OpenAPI-generated soon
packages/filter-engine   pure-TS dietary filter (web + mobile + tests)
packages/ui-tokens       shared design tokens
packages/eslint-config   flat config
_legacy/      frozen 2020 Rails 4.2 codebase, read-only
docs/adr/     architecture decision records
```

`pnpm-workspace.yaml` covers `apps/web`, `apps/mobile`, and `packages/*`.
Rails sits as its own folder with its own Bundler dependency tree. Turbo
runs the JS side; `bin/rails` runs the Rails side.

## Consequences

**Positive**
- Filter logic is *one* TypeScript file, identical on web and mobile, with
  a Vitest suite. Same shape mirrored on the Rails side as Active Record
  scopes. No drift.
- ltree + GIN-indexed UUID arrays on `items.ingredient_ids` give us
  sub-millisecond "hide everything containing X" queries at any plausible
  scale.
- AI-assisted ingestion targets the existing data model directly — vision
  models output our exact shape.
- Apple/Google sign-in from day one means App Store review never blocks us.
- Solid Queue removes Redis from the stack. One database, one bill.

**Negative**
- Two front-end runtimes (Next + Expo) is more complexity than a single
  Hotwire surface. Mitigated by sharing `packages/filter-engine` and
  `packages/ui-tokens`.
- Rails OpenAPI / TypeScript-codegen pipeline is a project itself —
  hand-written types in `packages/api-types` until rswag is wired up.
- Rewriting drops every existing user. No production data exists, so this
  is fine, but rules out an "upgrade in place" PR series.
- New stack means new bugs — older Rails apps had years of edge-case
  fixes baked into the 2020 code.

## Alternatives considered

- **Rails 8 + Hotwire only.** Simpler, but the dietary-filter UX (toggle,
  re-rank, transparency overlays) reads as a SPA and a true mobile app —
  Hotwire would have us reinventing both surfaces. Mobile is the primary
  use case (phone-in-restaurant), and "Hotwire on the web, native shell
  on iOS" doesn't get us a real App Store presence.
- **Next.js + Postgres, no Rails.** Tempting for a JS-only team, but the
  ingestion pipeline, jobs, and admin tooling are exactly what Rails
  excels at. Active Record scopes + Solid Queue + ActiveStorage replace
  three NPM packages with one mature framework.
- **Native iOS / Android (Swift/Kotlin).** Best UX, but doubles the team
  size and cuts shared code to zero. Reconsider after PMF.
