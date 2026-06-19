# Phase 2 — AI ingestion MVP (subplan)

Phase 2 turns "I have a paper menu" into "the items are staged in our database with ingredient + tag suggestions" in under a minute, then "five minutes of swipe-verify and the restaurant is live." The pipeline reads the existing v2 schema (`docs/schema.md`) directly — vision-capable Claude outputs the exact JSON shape the `IngestionItem` model already expects.

`docs/ingestion.md` is the long-form prose. This file decomposes it into PR-sized tasks the loop can take one at a time.

**Demo at the end:** photograph a real Durango menu in person; 60 seconds later the items appear staged in `/admin → Ingestion runs`; 5 minutes of swiping promotes them to live.

## Stop conditions specific to Phase 2

The loop should pause and ping `@shadoath` on these:

- **Anthropic API key** — `ANTHROPIC_API_KEY` is not in CI. Tasks that need a live call (2.3, 2.4) ship with VCR cassettes recorded against a real key locally; CI replays from cassette. The loop CAN'T record new cassettes — those need a human with the key.
- **Camera permissions / Apple signing** — Phase 2.7 (mobile camera capture) needs Apple/Google permissions plumbing. The Apple signing key is the same one that's deferred from Phase 1.2; if it's still not in CI when 2.7 lands, ship the JS layer and skip iOS-build CI.
- **R2 / S3 bucket** — ActiveStorage uploads need an `S3_BUCKET` and credentials. If unset, fall back to local disk in dev/test (already the default) but flag in the PR description.

## Tasks (one PR each)

### 2.1 — AnthropicClient service

**Branch**: `claude/phase-2.1-anthropic-client`

A thin Faraday wrapper around the Anthropic REST API. Handles:
- Bearer auth (reads `ANTHROPIC_API_KEY` ENV).
- Prompt caching: every system message that includes the taxonomy is sent with `cache_control: { type: "ephemeral" }` on the relevant block.
- Vision input: accepts a `[{type: "image", source: {data, media_type}}]` content block alongside text.
- Structured output: passes a JSON Schema in the request and validates the response against it. Returns parsed Ruby objects.
- Retries: faraday-retry on 429/5xx with exponential backoff; cap at 3.
- Errors: raises `AnthropicClient::ApiError` with the upstream response code + body so jobs can transition `IngestionRun` to `failed` with a useful audit message.

**Implementation notes**:
- Live in `app/services/anthropic_client.rb` and `app/services/anthropic_client/*.rb` for the helpers (PromptBuilder, ResponseParser, etc.).
- Use the `anthropic-version: 2023-06-01` header.
- Default model: `claude-sonnet-4-6` (current production model per ADR 0001).

**Specs**: VCR cassettes for one happy-path extraction, one cached follow-up, one validation failure. Cassettes go in `spec/cassettes/anthropic_client/`; `.env.example` documents how to record fresh ones.

**Acceptance**:
- `AnthropicClient.new.extract_menu(image_blob, system_prompt: ...)` returns a parsed object matching the `MenuExtraction` JSON Schema.
- Re-running the same call within the cache TTL hits the cache (`X-Anthropic-Cache-Hit` header check in VCR cassette).

### 2.2 — IngestionRun + IngestionItem state machine

**Branch**: `claude/phase-2.2-ingestion-state-machine`

The models exist (`app/models/ingestion_run.rb`, `ingestion_item.rb`) — this PR fleshes out the state transitions and validation.

States (`IngestionRun.status`):
- `queued` → `extracting` → `resolving` → `staged` → `published`
- Any state → `failed` (with `failure_message`)

Transitions (`IngestionRun#transition_to!(:extracting)` etc.):
- Idempotent — re-calling with the current state is a no-op.
- Records `transitioned_at` timestamps per state in a `state_history jsonb` column (new migration).
- Emits a Solid Queue job for the *next* stage when entering `extracting` / `resolving` / `staged`.

`IngestionItem.decision` enum: `pending | accepted | rejected | edited` (already in the schema). Add a `promote!` method that materializes the staged ingredient/tag payloads into real `Item` + `ItemIngredient` + `ItemTag` rows with `confidence: confirmed, source: human` (since a human just clicked accept).

**Specs**:
- Each transition fires the right next job (mock `ExtractMenuJob.perform_later` etc.).
- Re-transitioning is idempotent.
- `IngestionItem#promote!` creates the join rows + syncs the denormalized arrays via the existing `after_save` callbacks.

### 2.3 — ExtractMenuJob

**Branch**: `claude/phase-2.3-extract-menu-job`

Solid Queue job. Takes an `IngestionRun.id`, calls `AnthropicClient.extract_menu` with the run's attached blob, parses the response, and writes raw extracted items to a `staging` jsonb on the run. Transitions to `:resolving` on success, `:failed` with the API error on failure.

**Specs**: VCR-cassette-backed integration test that takes a fixture menu image (commit a small one to `spec/fixtures/menus/`), runs the job inline, asserts `IngestionRun` ends `resolving` + `staging` is populated.

**Stop**: needs `ANTHROPIC_API_KEY` for cassette recording. Pause + ping if cassettes are missing and a recording attempt is needed.

### 2.4 — ResolveIngredients + ResolveTags jobs

**Branch**: `claude/phase-2.4-resolve-jobs`

Two jobs that run in sequence after `ExtractMenuJob`. Each takes an `IngestionRun`, walks `staging[:items]`, calls `AnthropicClient` again with the relevant catalog (ingredients OR tags) cached in the system prompt, and writes resolved `[{slug, confidence}]` arrays back to staging.

Unknown strings land in `unresolved_ingredients[]` / `unresolved_tags[]` for human curation.

After both jobs complete, transitions the run to `:staged` and creates `IngestionItem` rows with `decision: pending`.

**Specs**: VCR cassettes per resolution call, plus a unit test for the unknown-string handling.

### 2.5 — Item promotion + admin verify UI

**Branch**: `claude/phase-2.5-promote-and-admin`

Phase 1.5's Avo dashboard gets two new resource customizations:
- `Avo::Resources::IngestionRun` shows the staging payload pretty-printed + a "Re-extract" action.
- `Avo::Resources::IngestionItem` shows side-by-side "AI suggested" vs "what would be saved" panels with Accept / Edit / Reject actions. Accept calls `IngestionItem#promote!` (from 2.2).

When a run hits ≥80% accepted (configurable per restaurant), the run flips to `published` and the restaurant flips to `status: 'published'` if it isn't already.

**Specs**: request specs for the Avo controller actions; unit tests for the threshold logic.

### 2.6 — Mobile multi-page camera capture + upload

**Branch**: `claude/phase-2.6-mobile-camera`

Expo `expo-camera` flow: tap "scan menu", capture multi-page (page-1 → page-2 → ...), preview thumbnails, retake / delete, "Upload all" submits to `POST /api/v1/ingestion_runs` with the images as multipart.

New API endpoint: `POST /api/v1/ingestion_runs` creates an `IngestionRun` with `restaurant_id` (authenticated user must have admin or contributor role — gated for now with `is_admin?` until Phase 4 introduces contributor accounts), attaches the images, transitions to `:queued` which fires `ExtractMenuJob`.

**Specs**:
- API: request spec covering happy path + auth gate.
- Mobile: Jest snapshot tests for the camera + upload screens; e2e in Phase 5.

### 2.7 — Mobile swipe-verify UI

**Branch**: `claude/phase-2.7-mobile-swipe-verify`

After upload, the mobile app polls `GET /api/v1/ingestion_runs/:id` until status hits `staged`, then opens a Tinder-style swipe deck of `IngestionItem`s. Right swipe = accept, left swipe = reject, tap = edit. Swipes hit `PATCH /api/v1/ingestion_runs/:run_id/items/:id` with `{decision: accepted|rejected|edited, ...}`.

**Specs**: API endpoints + Jest tests for the swipe gestures.

### 2.8 — Web: paste-URL / upload-PDF entrypoint

**Branch**: `claude/phase-2.8-web-ingestion-entry`

Next.js page at `/ingest` (admin-gated for now). Two surfaces:
- A textarea + "scrape this URL" → `POST /api/v1/ingestion_runs` with `source_type: "url"`. New URL-fetcher service in `apps/api/app/services/url_fetcher.rb` downloads the page (HTML or PDF) and attaches it as the input blob. Anthropic vision handles PDF directly.
- A file dropzone for direct PDF upload.

Same backend pipeline from 2.3 onward kicks in.

### 2.9 — Cost + latency dashboard in admin

**Branch**: `claude/phase-2.9-cost-dashboard`

Avo dashboard surface (Pro feature — IF licensed, otherwise hand-roll a small Avo tool action + Rails view) showing:
- Per-run cost in cents (sum of `IngestionRun.api_cost_cents`).
- Average extraction latency, p50/p95.
- Cache hit rate per day.
- "$0.25 per 50-item menu" target line.

Backed by columns added to `IngestionRun` in 2.1's migration: `api_cost_cents int`, `latency_ms int`, `cached_input_tokens int`, `uncached_input_tokens int`.

## Cross-cutting

- **VCR config**: add `vcr` gem to the test group; configure to record-once (`new_episodes` for local dev, `none` in CI).
- **Cost test**: the spec suite asserts that prompt caching is configured (the `cache_control` block is present in the request body). Catches regressions where the cache parameter falls off and costs explode.

## Out of scope for Phase 2

- Multi-language menu support (Phase 5).
- Real-time progress events (Phase 3 will use Solid Cable for the swipe-verify polling → push pivot).
- Cost-cap circuit breaker (defer until we see real spending patterns).
