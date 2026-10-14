'use client';

import { useEffect } from 'react';
import { usePathname } from 'next/navigation';
import { captureAdClick, sendMetaEvent } from '../lib/meta-pixel';
import { analyticsAllowed } from '../lib/track';

/**
 * Meta Pixel PageView on each allowed page. Client-only: the requests
 * live in `lib/meta-pixel.ts` and fire from this effect, never from SSR
 * HTML. Consent (`analyticsAllowed`: DNT + `bw_analytics_opt_out`) and
 * Global Privacy Control are checked before any request; admin routes
 * are skipped here and by the path allowlist.
 *
 * WBW-173 — `captureAdClick` reads `fbclid` first, then `sendMetaEvent`
 * sends a path-only image request whose URL and extra params are
 * sanitized. The live URL is not rewritten. Meta's own script is
 * never loaded, so autoConfig (button-text scraping) cannot run.
 */
export function MetaPixelProvider() {
  const pathname = usePathname();

  useEffect(() => {
    if (pathname.startsWith('/admin') || !analyticsAllowed()) return;
    captureAdClick();
    sendMetaEvent('PageView');
  }, [pathname]);

  return null;
}

/** A completed sign-up, sent from the sign-up page (its path only). */
export function markMetaRegistration(): void {
  sendMetaEvent('CompleteRegistration');
}
