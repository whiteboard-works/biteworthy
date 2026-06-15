/**
 * Phase 5.8 — web tracker wiring.
 *
 * Returns a `Tracker` from `@biteworthy/analytics`. The returned
 * tracker is `noopTracker` when:
 *
 *   * `NEXT_PUBLIC_POSTHOG_KEY` is unset (dev / CI / no-credentials)
 *   * The browser sends `Do-Not-Track: 1`
 *   * The user has opted out via the in-app analytics toggle
 *     (`localStorage.bw_analytics_opt_out === '1'`)
 *
 * Otherwise it constructs a tracker around the injected
 * `AnalyticsClient`. The client is supplied by `_PostHogProvider`,
 * which initializes `posthog-js` and passes
 * `createPostHogClient(posthog)` in. When no client is injected (SSR,
 * tests, or any caller outside the provider) the tracker stays
 * `noopTracker` — an apiKey alone is not enough to make it live.
 */

import {
  createTracker,
  noopTracker,
  type AnalyticsClient,
  type Tracker,
} from '@biteworthy/analytics';

const OPT_OUT_KEY = 'bw_analytics_opt_out';

interface BuildOptions {
  /** Test override; defaults to `process.env.NEXT_PUBLIC_POSTHOG_KEY`. */
  apiKey?: string | null;
  /** Test override for `navigator.doNotTrack`. */
  doNotTrack?: boolean;
  /** Test override for the localStorage opt-out flag. */
  optedOut?: boolean;
  /**
   * The constructed AnalyticsClient — a configured posthog-js instance
   * in production (injected by `_PostHogProvider`), or a mock in tests.
   * When absent the tracker no-ops even if `apiKey` is set: a live
   * tracker requires an injected client.
   */
  client?: AnalyticsClient | null;
}

export function buildWebTracker(opts: BuildOptions = {}): Tracker {
  const apiKey = opts.apiKey !== undefined ? opts.apiKey : process.env.NEXT_PUBLIC_POSTHOG_KEY;
  if (!apiKey) return noopTracker;

  const dnt = opts.doNotTrack !== undefined ? opts.doNotTrack : detectDoNotTrack();
  if (dnt) return noopTracker;

  const optedOut = opts.optedOut !== undefined ? opts.optedOut : detectOptOut();
  if (optedOut) return noopTracker;

  if (!opts.client) {
    // No client injected (SSR, tests, or a caller outside
    // _PostHogProvider) — an apiKey alone doesn't make a live tracker.
    return noopTracker;
  }
  return createTracker({ client: opts.client });
}

function detectDoNotTrack(): boolean {
  if (typeof navigator === 'undefined') return false;
  const dnt =
    (navigator as { doNotTrack?: string }).doNotTrack ??
    (window as unknown as { doNotTrack?: string }).doNotTrack;
  return dnt === '1' || dnt === 'yes';
}

function detectOptOut(): boolean {
  if (typeof localStorage === 'undefined') return false;
  try {
    return localStorage.getItem(OPT_OUT_KEY) === '1';
  } catch {
    return false;
  }
}

export { OPT_OUT_KEY };
