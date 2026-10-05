'use client';

import { useEffect, useState } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';

/**
 * Shows a brief success confirmation when landing here from onboarding.
 * Dismissible, auto-hides after 8s, and removed from URL on dismiss so
 * a refresh doesn't re-show it. Kept minimal per filter-loop.md.
 */
export function OnboardingSuccess() {
  const params = useSearchParams();
  const router = useRouter();
  const [visible, setVisible] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => {
    if (params.get('from_onboarding') === '1') {
      setMessage(params.get('message') || 'Profile saved');
      setVisible(true);

      // Auto-hide after 8s
      const timer = setTimeout(() => {
        dismiss();
      }, 8000);

      return () => clearTimeout(timer);
    }
  }, [params]);

  const dismiss = () => {
    setVisible(false);
    // Clean URL so a refresh doesn't re-show the banner
    router.replace('/restaurants');
  };

  if (!visible) return null;

  return (
    <div
      className="mb-bw-6 flex items-start justify-between gap-bw-3 rounded-bw-md border border-ok/40 bg-ok/10 px-bw-4 py-bw-3"
      data-testid="onboarding-success"
    >
      <p className="text-bw-sm font-semibold text-ok-dark">
        ✓ Profile saved, {message}. Browse menus below.
      </p>
      <button
        type="button"
        onClick={dismiss}
        aria-label="Dismiss"
        className="shrink-0 text-bw-lg font-bold text-ok-dark hover:text-ok"
      >
        ×
      </button>
    </div>
  );
}
