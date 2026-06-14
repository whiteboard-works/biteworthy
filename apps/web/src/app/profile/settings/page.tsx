'use client';

import { useEffect, useState } from 'react';
import { OPT_OUT_KEY } from '../../../lib/track';

/**
 * Legal remediation E7a — the analytics opt-out the Privacy Policy
 * promises ("turn them off with the toggle in /profile/settings").
 *
 * Web analytics are on by default (the wrapper also honors the
 * browser's Do-Not-Track). This toggle writes the same
 * `localStorage.bw_analytics_opt_out` flag that `buildWebTracker`
 * reads, so flipping it off makes the tracker a no-op on the next
 * load. We never send the dietary profile on analytics events
 * regardless (see packages/analytics — profile_set carries no health
 * fields).
 */
export default function ProfileSettingsPage() {
  // null until we've read localStorage (avoids an SSR/client mismatch).
  const [optedOut, setOptedOut] = useState<boolean | null>(null);

  useEffect(() => {
    try {
      setOptedOut(localStorage.getItem(OPT_OUT_KEY) === '1');
    } catch {
      setOptedOut(false);
    }
  }, []);

  const setOptOut = (next: boolean) => {
    try {
      if (next) localStorage.setItem(OPT_OUT_KEY, '1');
      else localStorage.removeItem(OPT_OUT_KEY);
    } catch {
      // localStorage unavailable (private mode) — nothing to persist.
    }
    setOptedOut(next);
  };

  const analyticsOn = optedOut === false;

  return (
    <main className="mx-auto max-w-2xl px-bw-6 pt-bw-12 pb-bw-16">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Settings</h1>

      <section className="mt-bw-8">
        <h2 className="text-bw-lg font-bold text-zinc-900">Product analytics</h2>
        <p className="mt-bw-2 text-bw-sm text-zinc-600">
          We use privacy-respecting product analytics to understand the launch funnel. Events are
          never tied to your dietary profile — we don’t send what you avoid, your presets, or your
          strictness. We also honor your browser’s Do-Not-Track signal automatically.
        </p>

        <label className="mt-bw-4 flex items-center justify-between rounded-bw-md border border-zinc-200 p-bw-4">
          <span className="text-bw-base font-semibold text-zinc-800">
            Allow anonymous product analytics
          </span>
          <input
            type="checkbox"
            role="switch"
            aria-label="analytics-opt-in"
            disabled={optedOut === null}
            checked={analyticsOn}
            onChange={(e) => setOptOut(!e.target.checked)}
            className="h-5 w-5"
          />
        </label>

        <p className="mt-bw-2 text-bw-xs text-zinc-500" data-testid="analytics-state">
          {optedOut === null
            ? 'Loading…'
            : analyticsOn
              ? 'Analytics are on. Turning this off takes effect on your next page load.'
              : 'Analytics are off. You’ve opted out on this device.'}
        </p>
      </section>
    </main>
  );
}
