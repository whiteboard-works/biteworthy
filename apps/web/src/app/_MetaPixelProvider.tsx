'use client';

import { useEffect } from 'react';
import { usePathname } from 'next/navigation';
import { captureAdClick, sendMetaEvent } from '../lib/meta-pixel';

/**
 * Meta Pixel PageView on each allowed page. The rules live in
 * `lib/meta-pixel-policy.ts`, the requests in `lib/meta-pixel.ts`, and the
 * privacy policy describes both. Meta's own script is never loaded.
 */
export function MetaPixelProvider() {
  const pathname = usePathname();

  useEffect(() => {
    captureAdClick();
    sendMetaEvent('PageView');
  }, [pathname]);

  return null;
}

/** A completed sign-up, sent from the sign-up page (its path only). */
export function markMetaRegistration(): void {
  sendMetaEvent('CompleteRegistration');
}
