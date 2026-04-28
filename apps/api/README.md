# BiteWorthy API

Rails 8 JSON API. Lives at `apps/api/` inside the monorepo.

## Local setup

```bash
cd apps/api
bundle install
bin/rails db:create db:schema:load db:seed
bin/rails s -p 3000
```

Postgres 16+ with `ltree`, `pg_trgm`, `pgcrypto`, and `citext` extensions.
The migrations enable them automatically (your role needs `CREATE EXTENSION`
privilege the first time).

## Routes

All app traffic lives under `/api/v1`. `/up` is the health check.
`/api-docs` renders the OpenAPI spec via rswag (Phase 1 work-in-progress).

## Background jobs

Solid Queue runs in the same Postgres database as the app. Boot it inline
with `SOLID_QUEUE_IN_PUMA=true bin/rails s` or as its own process with
`bin/jobs`.

## Tests

```bash
bundle exec rspec
```

## Where things live

| Concern | Path |
|---|---|
| Migrations | `db/migrate/` |
| Seed taxonomy (YAML) | `db/seeds/{tags,ingredients,dietary_profiles}.yml` |
| Models | `app/models/` |
| API controllers | `app/controllers/api/v1/` |
| Ingestion services (Anthropic) | `app/services/ingestion/` |
| Background jobs | `app/jobs/` |
