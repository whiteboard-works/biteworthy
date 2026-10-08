'use client';

import Script from 'next/script';
import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { analyticsAllowed } from '../lib/track';
import { globalPrivacyControl, metaPixelPathAllowed } from '../lib/meta-pixel-policy';

/**
 * Meta Pixel provider. Loads the Meta Pixel (ID 1775852390205529, shared
 * across all WBW sites) and sends PageView, but only where the privacy
 * policy says it may.
 *
 * Meta receives the page's full address with every event, so each event
 * is gated on `metaPixelPathAllowed`. That is an allowlist of public pages
 * that refuses any query string, because restaurant links carry the
 * chosen diet as `?profile=…`. Meta's own automatic history tracking
 * (`disablePushState`) and its automatic click and page-metadata
 * collection (`autoConfig`) are off, so only the PageView sent here leaves
 * the browser. There is no <noscript> image either, because its request
 * would carry the full address. The analytics opt-out, Do Not Track, and
 * Global Privacy Control each switch the pixel off entirely.
 */

const PIXEL_ID = '1775852390205529';
const CONTENT_NAME = 'BiteWorthy';

declare global {
  interface Window {
    fbq?: ((
      action: 'init' | 'track' | 'trackCustom' | 'set',
      eventName: string,
      ...params: unknown[]
    ) => void) & { disablePushState?: boolean };
    _fbq?: Window['fbq'];
    __bwMetaReady?: () => void;
  }
}

function consented(): boolean {
  return analyticsAllowed() && !globalPrivacyControl();
}

/** True when the current page may send anything to Meta. */
function allowedHere(): boolean {
  return (
    typeof window !== 'undefined' &&
    consented() &&
    metaPixelPathAllowed(window.location.pathname, window.location.search)
  );
}

function pageView(): void {
  if (allowedHere() && window.fbq) window.fbq('track', 'PageView');
}

export function MetaPixelProvider() {
  const pathname = usePathname();
  // The script loads on the first allowed page, not on whatever page the
  // visit started on, and stays loaded after that.
  const [load, setLoad] = useState(false);

  useEffect(() => {
    if (!allowedHere()) return;
    if (!load) {
      window.__bwMetaReady = pageView;
      setLoad(true);
      return;
    }
    pageView();
  }, [pathname, load]);

  if (!load) return null;

  return (
    <Script
      id="meta-pixel-base"
      strategy="afterInteractive"
      dangerouslySetInnerHTML={{
        __html: `
          !function(f,b,e,v,n,t,s)
          {if(f.fbq)return;n=f.fbq=function(){n.callMethod?
          n.callMethod.apply(n,arguments):n.queue.push(arguments)};
          if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';
          n.queue=[];t=b.createElement(e);t.async=!0;
          t.src=v;s=b.getElementsByTagName(e)[0];
          s.parentNode.insertBefore(t,s)}(window, document,'script',
          'https://connect.facebook.net/en_US/fbevents.js');
          fbq.disablePushState = true;
          fbq('set', 'autoConfig', false, '${PIXEL_ID}');
          fbq('init', '${PIXEL_ID}');
          if (window.__bwMetaReady) window.__bwMetaReady();
        `,
      }}
    />
  );
}

/**
 * Track a Meta Pixel standard event. Fires only where a PageView may: the
 * event carries the page's address too.
 */
export function trackMetaEvent(eventName: string, params: Record<string, unknown> = {}): void {
  if (!allowedHere() || !window.fbq) return;
  window.fbq('track', eventName, { content_name: CONTENT_NAME, ...params });
}

export { PIXEL_ID, CONTENT_NAME };
