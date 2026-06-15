/**
 * Phase 5.8 — mobile tracker wiring.
 *
 * Returns a `Tracker` from `@biteworthy/analytics`. The returned
 * tracker is `noopTracker` when:
 *
 *   * `EXPO_PUBLIC_POSTHOG_KEY` is unset
 *   * The user has opted out via the in-app analytics toggle
 *
 * RN doesn't have a Do-Not-Track analog the way browsers do, so the
 * opt-in is explicit (default off until the user accepts in
 * `/settings/analytics`).
 *
 * The client is supplied by `_layout.tsx`, which constructs the
 * `posthog-react-native` instance and passes `createPostHogClient(...)`
 * in. When no client is injected (tests, or before init) the tracker
 * stays `noopTracker`. Same shape as the web wrapper.
 */

import {
  createTracker,
  noopTracker,
  type AnalyticsClient,
  type Tracker,
} from '@biteworthy/analytics';

interface BuildOptions {
  /** Test override; defaults to `process.env.EXPO_PUBLIC_POSTHOG_KEY`. */
  apiKey?: string | null;
  /** Test override for the analytics-opt-in flag. */
  optedIn?: boolean;
  /**
   * The constructed AnalyticsClient — the posthog-react-native instance
   * in production (injected by `_layout.tsx`), or a mock in tests. When
   * absent the tracker no-ops.
   */
  client?: AnalyticsClient | null;
}

export function buildMobileTracker(opts: BuildOptions = {}): Tracker {
  const apiKey = opts.apiKey !== undefined ? opts.apiKey : process.env.EXPO_PUBLIC_POSTHOG_KEY;
  if (!apiKey) return noopTracker;

  // Mobile defaults to opted-out for App Store privacy posture; the
  // user explicitly opts IN via /settings/analytics.
  const optedIn = opts.optedIn === true;
  if (!optedIn) return noopTracker;

  if (!opts.client) {
    // No client injected (tests, or before init) — same guard as web.
    return noopTracker;
  }
  return createTracker({ client: opts.client });
}
