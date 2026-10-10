import { useEffect, useRef, useState } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import PostHog from 'posthog-react-native';
import { noopTracker, type Tracker } from '@biteworthy/analytics';
import { buildMobileTracker } from '../lib/track';
import {
  createPostHogClient,
  POSTHOG_HOST,
  registerExtension,
  stopCapturing,
} from '../lib/posthog-client';
import { TrackerContext } from '../lib/tracker-context';
import { getAnalyticsOptIn, onAnalyticsOptInChange } from '../lib/analytics-prefs';

/**
 * Phase 5.8-wiring — root layout with PostHog provider.
 *
 * Mounts the PostHog client (project 652080) once at app start,
 * registers `extension: 'biteworthy'`, and fires `app_open` so the
 * launch funnel has a known first event. The tracker is exposed to
 * descendants via `TrackerContext` (mirrors the web pattern).
 *
 * Legal remediation E7b — mobile is opt-in by default: the tracker
 * stays `noopTracker` until the user enables analytics in
 * Settings → Analytics. That choice is persisted in expo-secure-store,
 * read here at boot, and watched afterwards: flipping the switch opts
 * the SDK client out (or back in) and swaps the tracker on the spot, so
 * "Off" is off now, not after a restart. `EXPO_PUBLIC_POSTHOG_OPT_IN=1`
 * still forces it on for local smoke testing.
 */
export default function RootLayout() {
  const [tracker, setTracker] = useState<Tracker>(noopTracker);
  const startedRef = useRef(false);
  const clientRef = useRef<PostHog | null>(null);

  useEffect(() => {
    if (startedRef.current) return;
    startedRef.current = true;

    let cancelled = false;
    const apiKey = process.env.EXPO_PUBLIC_POSTHOG_KEY;

    // One client for the app's life. Built on the first opt-in; an opt-out
    // stops it (`stopCapturing`: the flag, then the queue) rather than
    // discarding it, so a later opt-in is `optIn` on the same instance.
    const trackerFor = (optedIn: boolean): Tracker => {
      if (!apiKey) return noopTracker;
      if (!optedIn) {
        if (clientRef.current) void stopCapturing(clientRef.current);
        return noopTracker;
      }
      if (!clientRef.current) {
        clientRef.current = new PostHog(apiKey, {
          host: POSTHOG_HOST,
          // Only the named events in @biteworthy/analytics. The SDK's own
          // "Application Opened" and friends are on by default and are
          // not part of the contract `/privacy` describes.
          captureAppLifecycleEvents: false,
        });
        registerExtension(clientRef.current);
      }
      // The SDK persists an opt-out across launches; a fresh client after
      // an earlier "off" is still out until told otherwise.
      void clientRef.current.optIn();
      return buildMobileTracker({
        apiKey,
        optedIn: true,
        client: createPostHogClient(clientRef.current),
      });
    };

    // The funnel's first event, once per session of tracking: at boot on
    // whichever tracker we resolved (a no-op when opted out), and again if
    // the person turns analytics on mid-session, so that session does not
    // start in the middle. The native-bridge require is fine — this is a
    // screen — and avoids booting it for tests.
    const openWith = (next: Tracker) => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const { Platform } = require('react-native');
      next.track('app_open', { surface: Platform.OS === 'android' ? 'android' : 'ios' });
    };

    let live = false;
    const apply = (optedIn: boolean) => {
      const next = trackerFor(optedIn);
      setTracker(next);
      const nowLive = next !== noopTracker;
      if (nowLive && !live) openWith(next);
      live = nowLive;
    };

    (async () => {
      const optedIn = (await getAnalyticsOptIn()) || process.env.EXPO_PUBLIC_POSTHOG_OPT_IN === '1';
      if (cancelled) return;
      apply(optedIn);
      // Opted out at boot: app_open still fires, into the no-op.
      if (!optedIn) openWith(noopTracker);
    })();

    const unsubscribe = onAnalyticsOptInChange((optedIn) => {
      if (!cancelled) apply(optedIn);
    });

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, []);

  return (
    <TrackerContext.Provider value={tracker}>
      <StatusBar style="auto" />
      <Stack
        screenOptions={{
          headerShown: false,
        }}
      />
    </TrackerContext.Provider>
  );
}
