/**
 * Phase 5.8-wiring — posthog-react-native adapter for the mobile
 * tracker.
 *
 * Mirror of `apps/web/src/lib/posthog-client.ts`. The RN SDK has a
 * slightly different shape — it's a class you instantiate with
 * `new PostHog(key, options)` and `register()` is async — but the
 * `AnalyticsClient` boundary smooths that out.
 *
 * Project context: BiteWorthy's own PostHog project (id 652080, ADR 0009).
 * The token is `EXPO_PUBLIC_POSTHOG_KEY`, set on the production profile in
 * `eas.json` only (preview builds are QA traffic) — a public client token,
 * so it is config, not a secret. The
 * `extension` super property predates the dedicated project and stays so
 * saved insights that filter on it keep working.
 */

import type PostHog from 'posthog-react-native';
import type { PostHogPersistedProperty } from 'posthog-react-native';
import type { AnalyticsClient } from '@biteworthy/analytics';

export const EXTENSION_NAME = 'biteworthy';
export const POSTHOG_HOST = 'https://us.i.posthog.com';

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

// The SDK's persisted queue key. A type-only import keeps the native module
// out of this file (and out of jest); the enum's value is the string.
const QUEUE_KEY = 'queue' as PostHogPersistedProperty;

/**
 * What "Off" means while the app is open. `optOut` only sets a flag: the
 * next `capture` is refused, but whatever was queued before the flip would
 * still leave on the next flush, seconds after the person said no. So the
 * flag first, then the queue is emptied. Not `shutdown`: the same instance
 * is reused if they turn it back on.
 */
export async function stopCapturing(client: PostHog): Promise<void> {
  await client.optOut();
  client.setPersistedProperty(QUEUE_KEY, null);
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
