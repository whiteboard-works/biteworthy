'use client';

import Script from 'next/script';
import { useEffect, useRef, useState } from 'react';
import { usePathname } from 'next/navigation';
import { analyticsAllowed } from '../lib/track';
import {
  inlineUrlSanitizerSnippet,
  sanitizeCurrentUrl,
  sanitizeEventParams,
} from '../lib/sanitize-url';

/**
 * Meta Pixel provider — loads the Meta Pixel (ID 1775852390205529, shared
 * across all WBW sites) on public pages, fires PageView on initial load
 * and route changes, and respects the same DNT / opt-out checks as PostHog.
 *
 * WBW-173 — why this shape, not a "manual PageView" alone:
 *
 * Meta's fbq auto-collects `dl` (document.location) and `rl`
 * (document.referrer) on every event. A later `track('PageView')` with a
 * scrubbed path does not change those fields. There is no supported fbq
 * API to override `dl`.
 *
 * So we:
 *   1. Mount the Pixel Script only on the client, after
 *      `analyticsAllowed()` (DNT + `bw_analytics_opt_out`) and after
 *      `sanitizeCurrentUrl()` has `history.replaceState`'d secrets out
 *      of the address bar. SSR HTML must not contain `fbq('init')` —
 *      that was the live leak: `/r/<slug>?p=<token>` hit Meta before
 *      React could run.
 *   2. Repeat the same sanitizer as the first statements of the inline
 *      bootstrap, then `fbq('set','autoConfig',false,PIXEL_ID)` before
 *      init. autoConfig does not stop `dl`/`rl` collection (replaceState
 *      still required) but it does stop Meta scraping button text —
 *      allergen chips and diet presets, which /privacy says we never
 *      send.
 *   3. Re-sanitize on every route change and every `trackMetaEvent`.
 *
 * `document.referrer` is read-only. The first-hit `rl` is whatever
 * brought the visitor here (usually an external origin). After
 * replaceState, later same-origin navigations should refer to the
 * cleaned URL.
 */

const PIXEL_ID = '1775852390205529';
const CONTENT_NAME = 'BiteWorthy';

declare global {
  interface Window {
    fbq?: (...args: unknown[]) => void;
    _fbq?: Window['fbq'];
  }
}

export function MetaPixelProvider() {
  const pathname = usePathname();
  const initialPageViewFired = useRef(false);
  const [allowed, setAllowed] = useState(false);

  const isAdminRoute = pathname.startsWith('/admin');

  useEffect(() => {
    if (isAdminRoute || !analyticsAllowed()) {
      setAllowed(false);
      initialPageViewFired.current = false;
      return;
    }
    // Strip share tokens etc. before the Script below is allowed to mount.
    sanitizeCurrentUrl();
    setAllowed(true);
  }, [pathname, isAdminRoute]);

  useEffect(() => {
    if (!allowed || typeof window === 'undefined' || !window.fbq) return;

    if (!initialPageViewFired.current) {
      // Bootstrap PageView already fired from the inline script.
      initialPageViewFired.current = true;
      return;
    }

    sanitizeCurrentUrl();
    window.fbq('track', 'PageView');
  }, [allowed, pathname]);

  if (!allowed) return null;

  return (
    <Script
      id="meta-pixel-base"
      strategy="afterInteractive"
      dangerouslySetInnerHTML={{
        __html: `
          ${inlineUrlSanitizerSnippet()}
          !function(f,b,e,v,n,t,s)
          {if(f.fbq)return;n=f.fbq=function(){n.callMethod?
          n.callMethod.apply(n,arguments):n.queue.push(arguments)};
          if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';
          n.queue=[];t=b.createElement(e);t.async=!0;
          t.src=v;s=b.getElementsByTagName(e)[0];
          s.parentNode.insertBefore(t,s)}(window, document,'script',
          'https://connect.facebook.net/en_US/fbevents.js');
          fbq('set', 'autoConfig', false, '${PIXEL_ID}');
          fbq('init', '${PIXEL_ID}');
          fbq('track', 'PageView');
        `,
      }}
    />
  );
}

/**
 * Track a Meta Pixel standard event. Only fires when the Pixel is loaded
 * and analytics is allowed (not DNT, not opted out). Sanitizes the
 * current URL and any URL-like / sensitive event params first.
 */
export function trackMetaEvent(eventName: string, params: Record<string, unknown> = {}): void {
  if (typeof window === 'undefined' || !analyticsAllowed() || !window.fbq) return;
  sanitizeCurrentUrl();
  window.fbq('track', eventName, {
    content_name: CONTENT_NAME,
    ...sanitizeEventParams(params),
  });
}

export { PIXEL_ID, CONTENT_NAME };
