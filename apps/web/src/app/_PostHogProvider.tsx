'use client';

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  type ReactElement,
  type ReactNode,
} from 'react';
import posthog from 'posthog-js';
import { noopTracker, type Tracker } from '@biteworthy/analytics';
import { buildWebTracker } from '../lib/track';
import { createPostHogClient, initPostHog } from '../lib/posthog-client';

/**
 * Phase 5.8-wiring — root client provider for the WBW Cross-Product
 * PostHog project.
 *
 * Mounts once at the app root (apps/web/src/app/layout.tsx); inits
 * posthog-js with `NEXT_PUBLIC_POSTHOG_KEY`, registers the
 * `extension: 'biteworthy'` super-property, and fires the canonical
 * `app_open` event on first paint.
 *
 * Children read the tracker via `useTracker()`. When the key is
 * absent / DNT is on / the user has opted out, `useTracker()`
 * returns `noopTracker` and every call is zero-cost.
 */

const TrackerContext = createContext<Tracker>(noopTracker);

export function useTracker(): Tracker {
  return useContext(TrackerContext);
}

export function PostHogProvider({ children }: { children: ReactNode }): ReactElement {
  const trackerRef = useRef<Tracker | null>(null);
  const appOpenFired = useRef(false);

  if (trackerRef.current === null) {
    const apiKey = process.env.NEXT_PUBLIC_POSTHOG_KEY;
    if (apiKey && typeof window !== 'undefined') {
      initPostHog(posthog, apiKey);
      trackerRef.current = buildWebTracker({
        apiKey,
        client: createPostHogClient(posthog),
      });
    } else {
      trackerRef.current = noopTracker;
    }
  }

  const tracker = trackerRef.current;

  useEffect(() => {
    if (appOpenFired.current) return;
    appOpenFired.current = true;
    tracker.track('app_open', { surface: 'web' });
  }, [tracker]);

  // useMemo to avoid re-providing on every render; the tracker
  // identity is stable across renders (set once via the ref).
  const value = useMemo(() => tracker, [tracker]);

  return <TrackerContext.Provider value={value}>{children}</TrackerContext.Provider>;
}
