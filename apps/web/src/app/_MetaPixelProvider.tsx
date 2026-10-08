'use client';

import Script from 'next/script';
import { useEffect, useRef, useState } from 'react';
import { usePathname } from 'next/navigation';
import { analyticsAllowed } from '../lib/track';
import {
  globalPrivacyControl,
  metaPixelReferrerAllowed,
  metaPixelUrlAllowed,
} from '../lib/meta-pixel-policy';

/**
 * Meta Pixel provider. Loads the Meta Pixel (ID 1775852390205529, shared
 * across all WBW sites) and sends PageView, but only where the privacy
 * policy says it may.
 *
 * Meta receives the page's full address and its referrer with every
 * event, so each event is gated on `metaPixelUrlAllowed` (an allowlist of
 * public pages that refuses anything after "?" or "#", because restaurant
 * links carry the chosen diet as `?profile=…`) and on
 * `metaPixelReferrerAllowed`. The sign-up conversion is recorded when it
 * happens and sent from the next allowed page, so the pixel never runs on
 * a page with an email field. Meta's own automatic history tracking
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
    metaPixelUrlAllowed(window.location) &&
    metaPixelReferrerAllowed(document.referrer, window.location.origin)
  );
}

const PENDING_REGISTRATION = 'bw_meta_pending_registration';

function pageView(): void {
  if (!allowedHere() || !window.fbq) return;
  window.fbq('track', 'PageView');
  let pending = false;
  try {
    pending = sessionStorage.getItem(PENDING_REGISTRATION) === '1';
    if (pending) sessionStorage.removeItem(PENDING_REGISTRATION);
  } catch {
    // storage blocked: the conversion is lost, never the visitor's privacy
  }
  if (pending) window.fbq('track', 'CompleteRegistration', { content_name: CONTENT_NAME });
}

export function MetaPixelProvider() {
  const pathname = usePathname();
  // The script loads on the first allowed page, not on whatever page the
  // visit started on, and stays loaded after that.
  const [load, setLoad] = useState(false);
  // The script's own ready hook sends the first PageView; the effect run
  // caused by `setLoad(true)` must not send a second one.
  const justLoaded = useRef(false);

  useEffect(() => {
    if (!allowedHere()) return;
    if (!load) {
      window.__bwMetaReady = pageView;
      justLoaded.current = true;
      setLoad(true);
      return;
    }
    if (justLoaded.current) {
      justLoaded.current = false;
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
 * Record a completed sign-up. Nothing goes to Meta from the sign-up page;
 * the next allowed page's PageView sends CompleteRegistration with it.
 * Off entirely when the visitor has opted out.
 */
export function markMetaRegistration(): void {
  if (typeof window === 'undefined' || !consented()) return;
  try {
    sessionStorage.setItem(PENDING_REGISTRATION, '1');
  } catch {
    // storage blocked: skip the conversion
  }
}

export { PIXEL_ID, CONTENT_NAME };
