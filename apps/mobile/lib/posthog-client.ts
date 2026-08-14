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

/**
 * posthog-react-native 4.45+ narrowed event properties from
 * `Record<string, unknown>` to `{ [key: string]: JsonType }`, and the
 * type isn't re-exported from the package's main entry — derive it
 * from the method signature instead. The cast below is sound: every
 * payload reaching this adapter is JSON-serializable by construction
 * (`EventPropsMap` in @biteworthy/analytics only allows JSON shapes).
 */
type CaptureProperties = Parameters<PostHog['capture']>[1];

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
 *
 * **`identify` is implemented but deliberately never called.** No caller
 * exists in mobile or web, so PostHog keeps its random distinct ID and
 * funnel events are not linked to an account — which is what `/privacy`
 * and `/terms` now tell users. Calling this would newly associate
 * health-adjacent events with an identity, the exact linkage the E7
 * remediation removed from `profile_set` (see packages/analytics
 * EventPropsMap). If you wire it up, update both legal pages in the
 * same change.
 */
export function createPostHogClient(client: PostHog): AnalyticsClient {
  return {
    capture(eventName, props) {
      client.capture(eventName, props as CaptureProperties);
    },
    identify(distinctId, props) {
      client.identify(distinctId, props as CaptureProperties);
    },
    reset() {
      void client.reset();
    },
  };
}
