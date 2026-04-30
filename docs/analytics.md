# Analytics — event taxonomy

The 9 stable funnel events for Phase 5.8. Names + payload schemas are the contract between the call sites (web, mobile, api) and the dashboard. **Renaming any of these breaks downstream funnels** — add new optional fields freely; rename only with a coordinated dashboard update.

The canonical type definitions live in `packages/analytics/src/index.ts` (`EVENTS` map + `EventPropsMap`). When this doc and that file disagree, the type definitions win — they're the compile-time contract.

## Funnel

The conversion path the launch dashboards measure:

```
app_open  →  profile_set  →  menu_filtered  →  restaurant_tap
```

Plus engagement events (review_posted, suggestion_submitted, restaurant_claimed, share_link_copied, filter_changed) that don't fit the linear funnel but matter for retention.

## Events

### `app_open`
First event in every session. Fired by web on page load, by mobile on cold + warm app start.

| Field | Type | Notes |
|---|---|---|
| `surface` | `"web" \| "ios" \| "android"` | Set by the app boundary. |
| `distinct_id` | `string?` | Anonymous id, sticky across sessions until logout. |

### `profile_set`
Fired when the user finishes the 6-tap onboarding (Phase 3.2 / 3.8) OR updates their profile.

| Field | Type | Notes |
|---|---|---|
| `preset_slug` | `string \| null` | One of the curated DietaryProfiles, or null when manual. |
| `avoid_ingredient_count` | `number` | Final count after onboarding. |
| `avoid_tag_count` | `number` | Final count after onboarding. |
| `strictness` | `"relaxed" \| "balanced" \| "strict"` | The Phase 3.5 toggle value. |

### `menu_filtered`
Fired when the user lands on a filtered restaurant page and the items endpoint returns. Once per page render, not per item.

| Field | Type | Notes |
|---|---|---|
| `restaurant_slug` | `string` | |
| `visible_count` | `number` | Items the filter shows. |
| `hidden_count` | `number` | Items the filter hides. |
| `filter_source` | `string` | `"preset"`, `"user_profile"`, `"profile_token"`, or `"none"`. Mirrors the API's `filter.source`. |

### `restaurant_tap`
Fired when the user opens a restaurant page from a list. Server-side, the Phase 4.8 `RecordRestaurantVisitJob` doubles as this for authenticated users so the funnel works even when JS analytics is blocked.

| Field | Type | Notes |
|---|---|---|
| `restaurant_slug` | `string` | |
| `from` | `string` | Source list: `"home"`, `"search"`, `"durango_diet"`, `"history"`. |

### `filter_changed`
Fired when the user toggles strictness, switches preset, or manually adds/removes an avoid item.

| Field | Type | Notes |
|---|---|---|
| `kind` | `string` | `"strictness" \| "preset" \| "manual_avoid" \| "manual_unavoid"`. |
| `from` | `string?` | Old value. |
| `to` | `string?` | New value. |

### `review_posted`
Fired on successful review submission (Phase 4.3 + 4.4 + 4.5).

| Field | Type | Notes |
|---|---|---|
| `item_slug` | `string` | Item identifier. |
| `restaurant_slug` | `string` | |
| `rating` | `number` | 1–5. |
| `has_photo` | `boolean` | |

### `share_link_copied`
Fired when the user shares a filtered URL (Phase 3.9 web + mobile).

| Field | Type | Notes |
|---|---|---|
| `restaurant_slug` | `string` | |
| `via` | `string` | `"native_share"` (mobile sheet), `"clipboard"` (web copy), `"prompt_fallback"` (web with blocked clipboard). |

### `restaurant_claimed`
Fired when a claim succeeds (Phase 4.9). Two outcomes possible.

| Field | Type | Notes |
|---|---|---|
| `restaurant_slug` | `string` | |
| `decision` | `string` | `"auto_acceptable"` (domain match) or `"admin_review"`. |

### `suggestion_submitted`
Fired when a Suggestion is submitted (Phase 4.10). The follow-up `decideSuggestion` path doesn't emit a separate event in v1 — admin moderation lives in /admin and isn't part of the public funnel.

| Field | Type | Notes |
|---|---|---|
| `item_slug` | `string` | |
| `restaurant_slug` | `string` | |
| `kind` | `string` | `"add_ingredient"`, `"rename"`, etc. — see Phase 4.10. |

## Privacy posture

- **Web**: respects `navigator.doNotTrack === '1'`. Local opt-out via `localStorage.bw_analytics_opt_out = '1'` (set by /profile/settings).
- **Mobile**: opt-IN by default-off. App Store privacy screens get the truth — the app doesn't track until the user explicitly accepts in /settings/analytics.
- **No PII in props**: never put email, full name, address, or device IDs in the payload. Slugs + counts only. PostHog's standard anonymous-id model handles cross-session continuity.

## What ships in Phase 5.8 vs Phase 5.8-wiring

**Phase 5.8 (this PR)**:
- `@biteworthy/analytics` package: typed Tracker interface, EVENTS map, noopTracker, createTracker factory
- `apps/web/src/lib/track.ts` — env + DNT + opt-out aware wrapper that returns a tracker (currently always noop because no client is injected yet)
- `apps/mobile/lib/track.ts` — env + opt-in aware wrapper (same)
- This document
- `docs/adr/0006-analytics.md`

**Phase 5.8-wiring (follow-up)**:
- `pnpm add posthog-js -F @biteworthy/web` and `posthog-react-native -F @biteworthy/mobile`
- Construct the `AnalyticsClient` adapters around those SDKs and pass them into `buildWebTracker` / `buildMobileTracker`
- Instrument all 9 events at their call sites: `app_open` in `app/layout.tsx` + `app/_layout.tsx`; `menu_filtered` in `RestaurantClient.tsx` + `[id].tsx`; etc.
- Server-side `RecordRestaurantVisitJob` enrichment to also fire `restaurant_tap` to PostHog's server endpoint (so the funnel survives ad-blockers)

The split keeps each PR small + reviewable. The abstraction shipping first means subsequent wiring PRs are call-site-only — no risk of taxonomy drift.
