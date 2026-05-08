import { createContext, useContext } from 'react';
import { noopTracker, type Tracker } from '@biteworthy/analytics';

/**
 * Phase 5.8-wiring — React context for the mobile Tracker.
 *
 * Mounted at the root layout (apps/mobile/app/_layout.tsx). Screens
 * read it via `useTracker()`. When the env key is unset or the user
 * is opted out, `useTracker()` returns `noopTracker` and every call
 * is zero-cost.
 *
 * Lives in /lib (not /app) so non-screen modules (tests, helper
 * components) can import it without dragging in expo-router.
 */
export const TrackerContext = createContext<Tracker>(noopTracker);

export function useTracker(): Tracker {
  return useContext(TrackerContext);
}
