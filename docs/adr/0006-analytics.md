# ADR 0006: analytics provider (PostHog)

- **Date:** 2026-04-30
- **Status:** Accepted
- **Refines:** ADR 0001 (the stack pick named `Sentry` for errors but didn't pick a product analytics provider)

## Context

Phase 5.8 needs to measure the launch funnel:

```
app_open → profile_set → menu_filtered → restaurant_tap
```

Plus engagement (`review_posted`, `share_link_copied`, `restaurant_claimed`, `suggestion_submitted`, `filter_changed`).

The pick has to clear three bars:

1. **Cost at launch volume.** Durango-beta projects ~10k events/month for the first quarter. Free tier or sub-$20/mo target.
2. **Privacy posture for App Store.** App Privacy screens require honest disclosure of what we collect; tools that automatically harvest device IDs / IP fingerprints fail this without careful config.
3. **Web + RN parity.** One event taxonomy, two SDKs, same dashboard. Don't want to maintain two product-analytics surfaces.

## Decision

**PostHog Cloud** (https://posthog.com), accessed via the `posthog-js` (web) and `posthog-react-native` (mobile) SDKs in a follow-up wiring PR. This PR (Phase 5.8) ships only the typed abstraction + event taxonomy — same ship-the-wiring-first pattern as Phase 4.11.2 / Phase 5.1 / Phase 5.2 / Phase 5.3.

### Why PostHog over alternatives

| Provider | Why considered | Why not picked |
|---|---|---|
| **PostHog Cloud** | Free tier: 1M events/month + 5k recordings. Funnel + retention built-in. Native web + RN SDKs share an API. Privacy-friendly — no auto-fingerprinting. EU + US regions. | — picked. |
| Plausible | Privacy-first, GDPR-by-default. Tiny snippet. | No funnel-builder UI; would need to query Plausible's data API + roll our own. RN SDK is community-maintained, not first-party. |
| Mixpanel | Mature funnel UX. | Free tier capped at 20M events, but real cost kicks in fast at $25/mo. Default config is more aggressive on tracking than we want for App Store posture. |
| Amplitude | Strong analytics. | Lifetime free tier capped lower than PostHog; pricing scales steeply. |
| Segment + warehouse | Future-proof. | Overkill at launch volume. Adds a vendor + a warehouse + a query tool. Phase 6+ if at all. |

PostHog wins on the 3-bar test. The free tier is generous enough that Durango beta + the first 6 months of organic growth fit easily.

### Why use the SDK + abstraction layer, not the SDK directly

`@biteworthy/analytics` (this PR) defines a `Tracker` interface that web + mobile call into. The SDK is injected at the app boundary. Reasons:

1. **Provider portability.** If PostHog ever bites cost-wise, we swap the adapter at one place — every call site keeps working.
2. **Compile-time event-name + payload safety.** Misspelled event names become TS errors instead of split funnels in the dashboard. Property keys are checked too.
3. **Cheap testing.** Vitest + Jest test the abstraction with a fake `AnalyticsClient`; no need to mock posthog-js.

### Why ship abstraction-only first

This PR doesn't install `posthog-js` or `posthog-react-native`. The wrapper returns `noopTracker` even when an API key is set, until a follow-up PR injects a real client. Reasons:

1. **`posthog-js` is ~60KB** at the time of writing (gzipped) and adds a real bundle-size hit on the SSR landing pages. Worth a dedicated review pass.
2. **Wiring is a 9-call-site change** across web + mobile + api. Lumping it with the abstraction would make a 1500-line PR that's hard to review.
3. **Phase 5.8 acceptance** ("a real beta tester completes the full funnel") needs the wiring + a real PostHog account. Both are deferred until launch is closer.

The structural-only split mirrors:
- Phase 4.11.2 (schema + prompt + materialize, cassette deferred)
- Phase 5.1 (Dockerfile + fly.toml, fly auth login deferred)
- Phase 5.2 (SMTP config, Postmark account deferred)
- Phase 5.3 (storage.yml + backfill, Cloudflare R2 bucket deferred)
- Phase 5.4 (vercel.json + sitemap, Vercel project deferred)

Same playbook every time: loop ships wiring; humans drop credentials.

## What this PR ships

- `packages/analytics/` — new workspace package, zero deps, pure TS:
  - `Tracker` interface + `AnalyticsClient` (the SDK contract)
  - `EVENTS` map + `EventPropsMap` (type-safe per-event payload schema)
  - `noopTracker` (safe default when key/DNT/opt-out fails)
  - `createTracker({ client })` factory for injecting an SDK
  - 6 vitest cases
- `apps/web/src/lib/track.ts` — env + DNT + localStorage-opt-out aware wrapper. 5 vitest cases.
- `apps/mobile/lib/track.ts` — env + opt-in aware wrapper (App Store privacy posture: opt IN, not OUT). 4 jest cases.
- `docs/analytics.md` — human-readable taxonomy mirroring the type definitions.
- This ADR.

## What needs a human (Phase 5.8-wiring follow-up)

1. Sign up for PostHog Cloud, create a "BiteWorthy" project. Pick the US or EU region based on user-data-residency preference (no strong constraint — beta is Durango-only).
2. Generate a project API key.
3. `fly secrets set NEXT_PUBLIC_POSTHOG_KEY=$KEY` for web (it's a public key so prefix with NEXT_PUBLIC; PostHog separates ingest from query by host).
4. Set the same as `EXPO_PUBLIC_POSTHOG_KEY` in EAS / Vercel env (mobile bundle has no Fly).
5. Open a follow-up PR (`claude/phase-5.8-wiring`):
   - `pnpm add posthog-js -F @biteworthy/web`
   - `pnpm add posthog-react-native -F @biteworthy/mobile`
   - In `apps/web/src/lib/track.ts`, wrap the posthog-js instance into an `AnalyticsClient` adapter and pass it into `buildWebTracker`.
   - Mirror in mobile.
   - Instrument the 9 call sites listed in `docs/analytics.md`.

## Trade-offs

**Bundle cost on the SSR pages** — posthog-js is ~60KB gz. Defer it to a client-only entry once it lands; the SSR landing + `/durango/[diet]` pages should never load it server-side.

**Single provider for analytics + recordings** — PostHog also does session replay. We won't enable that at launch (App Store posture; user trust); it's available later if useful.

**Server-side fallback** — Phase 4.8's `RecordRestaurantVisitJob` already records authenticated visits as `restaurant_visits` rows. The wiring follow-up will additionally fire `restaurant_tap` to PostHog's HTTP endpoint server-side so ad-blockers don't break the funnel for authenticated users.

## Consequences

- **Cost** — projected $0/month at launch; ~$20/month if we somehow blow past 1M events.
- **Privacy** — PostHog supports anonymous-only mode and respects DNT when wired; Phase 5.8-wiring's job is to wire those flags. The taxonomy explicitly excludes PII.
- **Observability** — once wiring lands, the Phase 2.9 cost dashboard's "production health" tab (Phase 5.7 referenced this) can pull from PostHog's API instead of building bespoke charts.
- **Vendor lock-in** — mild. The `Tracker` abstraction means we can swap providers in a day; the call sites stay unchanged.
