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
 * Otherwise it constructs a tracker around an injected
 * `AnalyticsClient`. **Phase 5.8 ships the wrapper without
 * `posthog-js` as a hard dep** — the follow-up wiring PR adds the
 * package + replaces `null` below with the real client. Keeping
 * this file noop-by-default means we can ship + review the
 * abstraction without committing to a posthog-js install yet.
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
   * Test override / Phase-5.8-wiring hook: inject a constructed
   * AnalyticsClient (e.g. a configured posthog-js instance). When
   * absent + `apiKey` is set, the tracker still no-ops because we
   * haven't installed the SDK yet — Phase 5.8-wiring follow-up
   * fills this in.
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
    // Phase 5.8 ships without posthog-js installed. The presence of
    // an apiKey alone isn't enough — a follow-up PR injects the
    // real client here.
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
