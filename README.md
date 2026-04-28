# BiteWorthy

> **Scan any menu, see only what you can eat.**

A pocket food filter that turns any restaurant menu — independent or chain —
into a personalized shortlist in seconds. Built around dietary needs first:
allergies, intolerances, religious observance, lifestyle.

## Repository layout

```
biteworthy/
├── apps/
│   ├── api/         Rails 8 JSON API
│   ├── web/         Next.js 15 (App Router)
│   └── mobile/      Expo / React Native
├── packages/
│   ├── api-types/       TS types generated from the Rails OpenAPI spec
│   ├── filter-engine/   Shared dietary-filter logic (web + mobile)
│   ├── ui-tokens/       Shared design tokens
│   └── eslint-config/
├── _legacy/         Frozen 2020 Rails 4.2 codebase (read-only)
└── docs/
    ├── adr/         Architecture decision records
    └── ...
```

## Quickstart

Requires Ruby 3.3+, Node 22+, pnpm 10+, Postgres 16+.

```bash
pnpm install
pnpm dev          # boots api, web, and mobile concurrently via Turborepo
```

Each app also has its own README under `apps/<name>/`.

## Status

Pre-MVP. See `docs/adr/0001-stack.md` for the architectural picks and
`docs/roadmap.md` for the phase plan.
