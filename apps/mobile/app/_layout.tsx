import { useEffect, useRef, useState } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import PostHog from 'posthog-react-native';
import { noopTracker, type Tracker } from '@biteworthy/analytics';
import { buildMobileTracker } from '../lib/track';
import { createPostHogClient, registerExtension } from '../lib/posthog-client';
import { TrackerContext } from '../lib/tracker-context';
import { getAnalyticsOptIn } from '../lib/analytics-prefs';

/**
 * Phase 5.8-wiring — root layout with PostHog provider.
 *
 * Mounts the WBW Cross-Product PostHog client once at app start,
 * registers `extension: 'biteworthy'`, and fires `app_open` so the
 * launch funnel has a known first event. The tracker is exposed to
 * descendants via `TrackerContext` (mirrors the web pattern).
 *
 * Legal remediation E7b — mobile is opt-in by default: the tracker
 * stays `noopTracker` until the user enables analytics in
 * Settings → Analytics. That choice is persisted in expo-secure-store
 * and read here at boot. `EXPO_PUBLIC_POSTHOG_OPT_IN=1` still forces it
 * on for local smoke testing.
 */
export default function RootLayout() {
  const [tracker, setTracker] = useState<Tracker>(noopTracker);
  const startedRef = useRef(false);

  useEffect(() => {
    if (startedRef.current) return;
    startedRef.current = true;

    let cancelled = false;
    (async () => {
      const apiKey = process.env.EXPO_PUBLIC_POSTHOG_KEY;
      const optedIn = (await getAnalyticsOptIn()) || process.env.EXPO_PUBLIC_POSTHOG_OPT_IN === '1';

      let next: Tracker = noopTracker;
      if (apiKey && optedIn) {
        const client = new PostHog(apiKey, { host: 'https://us.i.posthog.com' });
        registerExtension(client);
        next = buildMobileTracker({ apiKey, optedIn: true, client: createPostHogClient(client) });
      }
      if (cancelled) return;
      setTracker(next);

      // Fire app_open once, on whichever tracker we resolved (a no-op
      // when opted out). The native-bridge require is fine — this is a
      // screen — and avoids booting it for tests.
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const { Platform } = require('react-native');
      next.track('app_open', { surface: Platform.OS === 'android' ? 'android' : 'ios' });
    })();

    return () => {
      cancelled = true;
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
