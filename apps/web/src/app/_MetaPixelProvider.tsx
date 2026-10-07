'use client';

import Script from 'next/script';
import { useEffect, useRef } from 'react';
import { usePathname } from 'next/navigation';
import { analyticsAllowed } from '../lib/track';

/**
 * Meta Pixel provider — loads the Meta Pixel (ID 1775852390205529, shared
 * across all WBW sites) on public pages, fires PageView on initial load
 * and route changes, and respects the same DNT / opt-out checks as PostHog.
 *
 * Pixel ID is kept in one constant; events use content_name: 'BiteWorthy'
 * to identify this product. Admin routes are excluded from tracking.
 */

const PIXEL_ID = '1775852390205529';
const CONTENT_NAME = 'BiteWorthy';

declare global {
  interface Window {
    fbq?: (
      action: 'init' | 'track' | 'trackCustom',
      eventName: string,
      params?: Record<string, unknown>,
    ) => void;
    _fbq?: Window['fbq'];
  }
}

export function MetaPixelProvider() {
  const pathname = usePathname();
  const initialPageViewFired = useRef(false);

  const isAdminRoute = pathname.startsWith('/admin');

  useEffect(() => {
    if (
      typeof window === 'undefined' ||
      !analyticsAllowed() ||
      !window.fbq ||
      isAdminRoute
    )
      return;

    if (!initialPageViewFired.current) {
      initialPageViewFired.current = true;
      return;
    }

    window.fbq('track', 'PageView');
  }, [pathname, isAdminRoute]);

  if (typeof window !== 'undefined' && (!analyticsAllowed() || isAdminRoute)) {
    return null;
  }

  return (
    <>
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
            fbq('init', '${PIXEL_ID}');
            fbq('track', 'PageView');
          `,
        }}
      />
      <noscript>
        <img
          height="1"
          width="1"
          style={{ display: 'none' }}
          src={`https://www.facebook.com/tr?id=${PIXEL_ID}&ev=PageView&noscript=1`}
          alt=""
        />
      </noscript>
    </>
  );
}

/**
 * Track a Meta Pixel standard event. Only fires when the Pixel is loaded
 * and analytics is allowed (not DNT, not opted out).
 */
export function trackMetaEvent(
  eventName: string,
  params: Record<string, unknown> = {},
): void {
  if (typeof window === 'undefined' || !analyticsAllowed() || !window.fbq) return;
  window.fbq('track', eventName, { content_name: CONTENT_NAME, ...params });
}

export { PIXEL_ID, CONTENT_NAME };
