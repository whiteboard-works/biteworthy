# Analytics — event taxonomy

The stable funnel + engagement events (9 core, plus 3 auth events). Names + payload schemas are the contract between the call sites (web, mobile, api) and the dashboard. **Renaming any of these breaks downstream funnels** — add new events + optional fields freely; rename only with a coordinated dashboard update.

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

**Legal remediation E7:** this is a funnel-conversion marker only. The dietary
profile is special-category health data, so `preset_slug`, `strictness`,
`avoid_ingredient_count`, and `avoid_tag_count` were **removed** — a health
condition must never be attached to an identified analytics event (memo Issue
6). Only the (non-health) taste-signal count remains.

| Field | Type | Notes |
|---|---|---|
| `taste_signal_count` | `number?` | Phase 8.5 — liked + disliked tags + ingredients set in the "What do you love?" step. Optional; absent when the step was skipped or for pre-8.5 callers. Taste (cuisine/flavor) is not health data. |

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

## Auth events

Auxiliary to the core funnel (they fire after `app_open`, before `profile_set`) — they measure the sign-in / sign-up flow so we can see conversion and *where* it breaks. **No PII**: never the email or password, only a coarse `method` / `reason` / `status`. Currently instrumented on **web** (`login/page.tsx`, `signup/page.tsx`, `forgot-password/page.tsx`, `reset-password/page.tsx`); mobile can adopt the same events.

### `auth_started`
Fired on every submit of the login or signup form (before validation), so it counts intent.

| Field | Type | Notes |
|---|---|---|
| `method` | `"login" \| "signup" \| "password_forgot" \| "password_reset"` | Which form was submitted. |

### `auth_completed`
Fired once the account is signed in (before the post-auth redirect). `auth_started → auth_completed` is the conversion funnel.

| Field | Type | Notes |
|---|---|---|
| `method` | `"login" \| "signup" \| "password_forgot" \| "password_reset"` | |

### `auth_failed`
Fired on any failure — both client-side gates and API errors — so drop-off is attributable.

| Field | Type | Notes |
|---|---|---|
| `method` | `"login" \| "signup" \| "password_forgot" \| "password_reset"` | |
| `reason` | `string` | Coarse category, never the raw error. Login: `missing_fields`, `wrong_credentials`, `server`, `network`, `unknown`. Signup adds the client gates (`weak_password`, `age_unconfirmed`, `terms_unaccepted`) and `rejected` for a server-side 422 (Rails returns 422 for any registration validation failure — duplicate email, invalid email, etc. — so it isn't labelled as specifically email-taken). |
| `status` | `number?` | Upstream HTTP status when the failure came from the API (401 / 422 / 5xx); absent for client-side gates and network errors. |

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

### Chat events (added with the chat-engine arc)

| Event | Props | Notes |
|---|---|---|
| `chat_started` | `surface` | Fires once per conversation created. |
| `chat_turn_completed` | `outcome`, `tool_count`, `duration_ms` | One completed turn. |
| `chat_confirmed` | `approved` | A person answered the confirmation gate. |

**These deliberately carry no message text and no tool names.** The same
reasoning that stripped the dietary profile off `profile_set` applies, and
is easier to miss here: a tool name like `update_avoid_lists` on an
identified event says this account edited a dietary profile, which is
health-adjacent even without the contents. Counts and outcome give the
funnel what it needs — did the turn work, how long, how much did it do.
