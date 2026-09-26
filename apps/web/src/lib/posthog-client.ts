/**
 * Phase 5.8-wiring — posthog-js adapter for the web tracker.
 *
 * Bridges the posthog-js SDK to the project-agnostic `AnalyticsClient`
 * interface in `@biteworthy/analytics`. The wrapper is intentionally
 * thin — every method is a passthrough — so swapping providers is a
 * single-file change.
 *
 * Project context: WBW Cross-Product (id 370116). All seven Whiteboard
 * Works sites share one PostHog project and differentiate via the
 * `extension` super-property registered at init time. Filtering in
 * the dashboard happens via that property.
 */

import type posthog from 'posthog-js';
import type { CaptureResult } from 'posthog-js';
import type { AnalyticsClient } from '@biteworthy/analytics';

export const EXTENSION_NAME = 'biteworthy';

/** Test seam — pass a posthog-js instance (or any compatible mock). */
export type PostHogJsInstance = typeof posthog;

/**
 * Initialize posthog-js with the cross-product key + register the
 * `extension: 'biteworthy'` super-property so every event carries it.
 *
 * Idempotent: call once at the React app boundary; subsequent calls
 * with the same key are a no-op (posthog-js handles re-init guards).
 */
export function initPostHog(
  client: PostHogJsInstance,
  apiKey: string,
  options: { apiHost?: string } = {},
): void {
  client.init(apiKey, {
    api_host: options.apiHost ?? 'https://us.i.posthog.com',
    person_profiles: 'identified_only',
    // Page views are how traffic shows up at all; client-side navigation
    // never re-fires `app_open`. Their URLs go through `scrubEvent`.
    capture_pageview: 'history_change',
    capture_pageleave: false,
    persistence: 'localStorage+cookie',
    // Only the named funnel events and page views. Autocapture sent the
    // text of whatever was clicked — a celiac preset, a chat message —
    // which /privacy promises we never send. Session replay is switched
    // on at the project level (shared with other sites), so it has to be
    // refused here explicitly.
    autocapture: false,
    rageclick: false,
    capture_dead_clicks: false,
    capture_heatmaps: false,
    disable_session_recording: true,
    // Also on at the shared project level; exceptions carry messages and
    // stack data, and neither is something /privacy discloses.
    capture_exceptions: false,
    capture_performance: false,
    // utm_term and friends can carry a search like "celiac tacos"; the
    // scrubber drops them too, this just stops the SDK storing them.
    save_campaign_params: false,
    // The /flags request carries the persisted initial URL and never passes
    // through before_send; nothing here uses feature flags.
    advanced_disable_flags: true,
    disable_surveys: true,
    before_send: scrubEvent,
  });
  client.register({ extension: EXTENSION_NAME });
  // Only called once our own consent check passed (_PostHogProvider), and
  // our flag is the source of truth: an earlier opt-out in /profile/settings
  // also persisted posthog-js's own denial, which would otherwise outlive
  // the visitor turning analytics back on.
  if (client.has_opted_out_capturing()) {
    // init() has already scheduled this load's page view; opting in with
    // page views on would capture a second one immediately.
    client.set_config({ capture_pageview: false });
    client.opt_in_capturing({ captureEventName: false });
    client.set_config({ capture_pageview: 'history_change' });
  }
}

/**
 * Adapter from posthog-js to `AnalyticsClient`. The interface exposes
 * three methods: capture, identify, reset.
 *
 * **`identify` is implemented but deliberately never called.** No caller
 * exists in web or mobile, so PostHog keeps its random distinct ID and
 * funnel events are not linked to an account — which is what
 * `/privacy` and `/terms` now tell users. Calling this would newly
 * associate health-adjacent events with an identity, the exact linkage
 * the E7 remediation removed from `profile_set`
 * (see packages/analytics EventPropsMap). If you wire it up, update both
 * legal pages in the same change.
 */
export function createPostHogClient(client: PostHogJsInstance): AnalyticsClient {
  return {
    capture(eventName, props) {
      client.capture(eventName, props);
    },
    identify(distinctId, props) {
      client.identify(distinctId, props);
    },
    reset() {
      client.reset();
    },
  };
}

// Any property whose name ends in url / pathname / referrer carries a URL:
// $current_url, $referrer, the $session_entry_* and $initial_* copies the
// SDK adds, and whatever it adds next. Matched by name so a new one is
// scrubbed by default rather than leaking until someone lists it.
const URL_KEY = /(url|pathname|referrer)$/i;

// Properties that repeat what someone searched or which page they read in
// words: the page title (a diet page's title names the diet), search
// keywords PostHog derives from a referrer, and campaign/ad-click params.
// Also matched on the $initial_ / $session_entry_ copies.
// posthog-js's own campaign/ad-click parameter list (1.434), plus the
// page title and derived search keyword.
const DROPPED_PARAMS = [
  'title',
  'ph_keyword',
  'keyword',
  'utm_[a-z_]+',
  'gad_source',
  'mc_cid',
  'gclid',
  'gclsrc',
  'dclid',
  'gbraid',
  'wbraid',
  'fbclid',
  'msclkid',
  'twclid',
  'li_fat_id',
  'igshid',
  'ttclid',
  'rdt_cid',
  'epik',
  'qclid',
  'sccid',
  'irclid',
  '_kx',
];
const DROP_KEY = new RegExp(`(^|[_$])(${DROPPED_PARAMS.join('|')})$`, 'i');

/**
 * Reduce a URL to what the dashboards need and nothing health-adjacent:
 * no query string or hash (share links carry an encoded avoid list,
 * `?profile=` names a diet), the diet out of `/durango/<diet>`, and the
 * person out of `/u/<handle>`.
 */
export function scrubUrl(value: string): string {
  let url: URL;
  const relative = value.startsWith('/');
  try {
    url = new URL(value, 'https://placeholder.invalid');
  } catch {
    // Unparseable: keep nothing that could carry a path or a query.
    return relative ? maskPath(value.split(/[?#]/)[0] ?? '') : '';
  }
  const path = maskPath(url.pathname);
  if (relative) return path;
  // A third-party referrer keeps only its origin.
  if (url.hostname !== window.location.hostname) return url.origin;
  return `${url.origin}${path}`;
}

function maskPath(path: string): string {
  return path.replace(/^\/durango\/[^/]+/, '/durango/:diet').replace(/^\/u\/[^/]+/, '/u/:handle');
}

function scrubProps(props: Record<string, unknown> | undefined): void {
  if (!props) return;
  for (const [key, v] of Object.entries(props)) {
    if (DROP_KEY.test(key)) delete props[key];
    else if (URL_KEY.test(key) && typeof v === 'string' && v !== '$direct')
      props[key] = scrubUrl(v);
  }
}

/** `before_send` hook: every event leaves the browser with scrubbed URLs. */
export function scrubEvent(event: CaptureResult | null): CaptureResult | null {
  if (!event) return event;
  scrubProps(event.properties);
  scrubProps(event.$set as Record<string, unknown> | undefined);
  scrubProps(event.$set_once as Record<string, unknown> | undefined);
  return event;
}
