import { useEffect, useMemo, useRef } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import PostHog from 'posthog-react-native';
import { noopTracker, type Tracker } from '@biteworthy/analytics';
import { buildMobileTracker } from '../lib/track';
import { createPostHogClient, registerExtension } from '../lib/posthog-client';
import { TrackerContext } from '../lib/tracker-context';

/**
 * Phase 5.8-wiring — root layout with PostHog provider.
 *
 * Mounts the WBW Cross-Product PostHog client once at app start,
 * registers `extension: 'biteworthy'`, and fires `app_open` so the
 * launch funnel has a known first event. The tracker is exposed to
 * descendants via `TrackerContext` (mirrors the web pattern).
 *
 * Mobile is opt-in by default: the tracker stays `noopTracker` until
 * the user accepts in /settings/analytics. The opt-in flag lives in
 * `expo-secure-store` (added in a follow-up; v1 of this PR keeps it
 * always-noop pending that wiring).
 */
export default function RootLayout() {
  const trackerRef = useRef<Tracker | null>(null);
  const appOpenFired = useRef(false);

  if (trackerRef.current === null) {
    const apiKey = process.env.EXPO_PUBLIC_POSTHOG_KEY;
    // Phase 5.8-wiring v1: opt-in toggle wiring lands in a follow-up.
    // Treat all real users as opted-out until then; this keeps the
    // App Store privacy posture honest. Set EXPO_PUBLIC_POSTHOG_OPT_IN=1
    // for local smoke testing.
    const optedIn = process.env.EXPO_PUBLIC_POSTHOG_OPT_IN === '1';
    if (apiKey && optedIn) {
      const client = new PostHog(apiKey, {
        host: 'https://us.i.posthog.com',
      });
      registerExtension(client);
      trackerRef.current = buildMobileTracker({
        apiKey,
        optedIn: true,
        client: createPostHogClient(client),
      });
    } else {
      trackerRef.current = noopTracker;
    }
  }

  const tracker = trackerRef.current;

  useEffect(() => {
    if (appOpenFired.current) return;
    appOpenFired.current = true;
    // Surface defaults to 'ios' on iOS, 'android' on Android. We
    // don't import Platform here just to avoid the native-bridge
    // boot for tests; the runtime require is fine because this
    // file is already a screen.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { Platform } = require('react-native');
    const surface = Platform.OS === 'android' ? 'android' : 'ios';
    tracker.track('app_open', { surface });
  }, [tracker]);

  const value = useMemo(() => tracker, [tracker]);

  return (
    <TrackerContext.Provider value={value}>
      <StatusBar style="auto" />
      <Stack
        screenOptions={{
          headerShown: false,
        }}
      />
    </TrackerContext.Provider>
  );
}
