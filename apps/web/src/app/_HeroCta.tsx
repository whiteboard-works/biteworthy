'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';

/**
 * The landing hero's primary CTA, adapted to auth state: a signed-in user
 * sees "Scan a menu" (the core action) instead of the onboarding CTA that a
 * new visitor gets. Reads the same fast `/api/auth/session` the header uses.
 *
 * Defaults to the signed-out CTA until auth resolves — most landing visitors
 * are logged out, so there's no swap for them; a signed-in user briefly sees
 * "Try the web app" before it flips to "Scan a menu."
 */
const CTA_CLASS =
  'rounded-bw-md bg-bite px-bw-6 py-bw-3 text-bw-base font-bold text-white shadow-sm hover:bg-bite-dark';

export function HeroCta() {
  const [signedIn, setSignedIn] = useState<boolean | null>(null);

  useEffect(() => {
    let active = true;
    fetch('/api/auth/session', { credentials: 'same-origin' })
      .then((r) => (r.ok ? r.json() : { signedIn: false }))
      .then((d: { signedIn?: boolean }) => {
        if (active) setSignedIn(Boolean(d.signedIn));
      })
      .catch(() => {
        if (active) setSignedIn(false);
      });
    return () => {
      active = false;
    };
  }, []);

  // Scanning a menu is a conversation now, so the core action for a
  // signed-in user is the chat rather than an upload form.
  if (signedIn) {
    return (
      <Link href="/chat" data-testid="cta-scan" className={CTA_CLASS}>
        Scan a menu →
      </Link>
    );
  }

  return (
    <Link href="/onboarding" data-testid="cta-web" className={CTA_CLASS}>
      Try the web app →
    </Link>
  );
}
