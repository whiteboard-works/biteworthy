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
    capture_pageview: false,
    capture_pageleave: false,
    persistence: 'localStorage+cookie',
  });
  client.register({ extension: EXTENSION_NAME });
}

/**
 * Adapter from posthog-js to `AnalyticsClient`. The interface exposes
 * three methods: capture, identify, reset.
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
