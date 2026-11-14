/**
 * Meta Pixel without Meta's script. Each event is one image request to
 * Meta's pixel endpoint, built here from `meta-pixel-policy`: the page's
 * path (never its query or hash), a cleaned referrer, and Meta's cookie
 * ids. Without `fbevents.js` in the page there is nothing of Meta's to
 * listen for history changes, back-forward restores, clicks, or form
 * fields, so nothing reaches Meta that this file did not send.
 *
 * WBW-173: `sanitizeUrl` / `sanitizeEventParams` scrub the outbound
 * pixel request and custom data (share tokens, diet presets, keys,
 * emails, hash payloads). The live URL is left alone so a reload and
 * the claim/login `next=` bounce still apply the shared filter.
 * autoConfig is never on because `fbevents.js` is never loaded.
 */
import { analyticsAllowed } from './track';
import {
  globalPrivacyControl,
  metaPageAddress,
  metaPixelPathAllowed,
  metaReferrer,
} from './meta-pixel-policy';
import { sanitizeEventParams, sanitizeReferrer, sanitizeUrl } from './sanitize-url';

export const PIXEL_ID = '1775852390205529';
export const CONTENT_NAME = 'BiteWorthy';
const ENDPOINT = 'https://www.facebook.com/tr';
const NINETY_DAYS = 90 * 24 * 60 * 60;

/** The analytics opt-out, Do Not Track, and Global Privacy Control each turn it off. */
export function metaConsented(): boolean {
  return typeof window !== 'undefined' && analyticsAllowed() && !globalPrivacyControl();
}

function readCookie(name: string): string | null {
  const hit = document.cookie.split('; ').find((c) => c.startsWith(`${name}=`));
  return hit ? decodeURIComponent(hit.slice(name.length + 1)) : null;
}

function writeCookie(name: string, value: string): void {
  const secure = window.location.protocol === 'https:' ? '; secure' : '';
  document.cookie = `${name}=${encodeURIComponent(value)}; max-age=${NINETY_DAYS}; path=/; samesite=lax${secure}`;
}

/**
 * An ad click lands with `?fbclid=…`. Keep it as Meta's `_fbc` cookie so a
 * later sign-up can be credited to the ad. The query itself is never sent
 * (dl is path-only; the pixel request URL is sanitized). The live URL is
 * left intact.
 */
export function captureAdClick(): void {
  if (!metaConsented()) return;
  const fbclid = new URLSearchParams(window.location.search).get('fbclid');
  if (fbclid) writeCookie('_fbc', `fb.1.${Date.now()}.${fbclid}`);
}

function browserId(): string {
  let fbp = readCookie('_fbp');
  if (!fbp) {
    fbp = `fb.1.${Date.now()}.${Math.floor(Math.random() * 1e10)}`;
    writeCookie('_fbp', fbp);
  }
  return fbp;
}

/**
 * Send one pixel event from the current page, if this page may. Returns
 * whether a request went out. Extra custom-data keys are sanitized
 * (sensitive names dropped, URL-like values scrubbed) before they are
 * attached — the path-only `dl` is still the address Meta sees.
 */
export function sendMetaEvent(
  event: 'PageView' | 'CompleteRegistration',
  extra: Record<string, unknown> = {},
): boolean {
  if (!metaConsented()) return false;
  const { origin, pathname } = window.location;
  if (!metaPixelPathAllowed(pathname)) return false;

  const params = new URLSearchParams({
    id: PIXEL_ID,
    ev: event,
    dl: metaPageAddress(origin, pathname),
    rl: metaReferrer(sanitizeReferrer(document.referrer), origin),
    ts: String(Date.now()),
    fbp: browserId(),
  });
  const fbc = readCookie('_fbc');
  if (fbc) params.set('fbc', fbc);

  const custom = sanitizeEventParams({
    ...(event !== 'PageView' ? { content_name: CONTENT_NAME } : {}),
    ...extra,
  });
  for (const [key, value] of Object.entries(custom)) {
    if (value === undefined || value === null) continue;
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
      params.set(`cd[${key}]`, String(value));
    }
  }

  const img = new Image();
  // The request must not carry the page's full address as its Referer.
  img.referrerPolicy = 'no-referrer';
  // Scrub the outbound pixel URL only — never `history.replaceState`.
  img.src = sanitizeUrl(`${ENDPOINT}?${params.toString()}`);
  return true;
}
