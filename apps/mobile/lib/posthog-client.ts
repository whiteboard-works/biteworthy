/**
 * Phase 5.8-wiring — posthog-react-native adapter for the mobile
 * tracker.
 *
 * Mirror of `apps/web/src/lib/posthog-client.ts`. The RN SDK has a
 * slightly different shape — it's a class you instantiate with
 * `new PostHog(key, options)` and `register()` is async — but the
 * `AnalyticsClient` boundary smooths that out.
 *
 * Project context: WBW Cross-Product (id 370116). All seven Whiteboard
 * Works sites share one PostHog project; this app sets the
 * `extension: 'biteworthy'` super-property so events can be filtered
 * to BiteWorthy in the dashboard.
 */

import type PostHog from 'posthog-react-native';
import type { AnalyticsClient } from '@biteworthy/analytics';

export const EXTENSION_NAME = 'biteworthy';

export type PostHogRNInstance = PostHog;

/**
 * Register the `extension` super-property. The RN SDK's `register` is
 * async (writes to AsyncStorage); fire-and-forget is fine because the
 * subsequent `capture` calls retry from the same persisted store on
 * reconnect — no events are lost if `register` settles after the
 * first capture.
 */
export function registerExtension(client: PostHog): void {
  void client.register({ extension: EXTENSION_NAME });
}

/**
 * Adapter from posthog-react-native to `AnalyticsClient`.
 */
export function createPostHogClient(client: PostHog): AnalyticsClient {
  return {
    capture(eventName, props) {
      client.capture(eventName, props);
    },
    identify(distinctId, props) {
      client.identify(distinctId, props);
    },
    reset() {
      void client.reset();
    },
  };
}
