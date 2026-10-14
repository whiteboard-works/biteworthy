/**
 * WBW-173 — sanitize URLs before third-party analytics sees them.
 *
 * Share links (`/r/<slug>?p=<token>`) encode the sharer's avoid-list IDs
 * and strictness. Diet-page links carry `?profile=celiac`. Meta's pixel
 * used to auto-collect `document.location` (dl) and `document.referrer`
 * (rl) on every event, which sent those values to Meta. The site no
 * longer loads `fbevents.js` (see `lib/meta-pixel.ts`); this sanitizer
 * is still the common rule for (1) `history.replaceState` of the live
 * URL before any pixel request, (2) any URL-like event params, and
 * (3) an inline snippet kept in lockstep if a bootstrap ever races
 * React.
 *
 * `document.referrer` is read-only — we sanitize any referrer we pass
 * ourselves, but we cannot change what the browser reports as `rl` on
 * the first hit from another site.
 *
 * Sensitive params (removed from both `?query` and `#hash`):
 *   - `p`, `profile` — share token / diet preset
 *   - `token`, `*_token` — auth tokens
 *   - `key`, `*_key`, `license_key` — API/license keys
 *   - `transaction_id`, `email`, `code`, `activate`, `activation`,
 *     `note`, `source_url`
 *   - the same campaign / ad-click params PostHog already drops
 */

export const SENSITIVE_PARAMS = [
  'p',
  'profile',
  'token',
  'key',
  'license_key',
  'transaction_id',
  'email',
  'activate',
  'activation',
  'code',
  'note',
  'source_url',
] as const;

// Marketing/tracking params PostHog already strips (`DROPPED_PARAMS` in
// posthog-client.ts) — keep both trackers consistent. `utm_*` is also
// matched by prefix in `isSensitiveParam`, so a new utm_foo is dropped
// without a list edit.
export const TRACKING_PARAMS = [
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'gad_source',
  'mc_cid',
  'gclid',
  'gclsrc',
  'dclid',
  'gbraid',
  'wbraid',
  'fbclid',
  'msclkid',
  'twclid',
  'li_fat_id',
  'igshid',
  'ttclid',
  'rdt_cid',
  'epik',
  'qclid',
  'sccid',
  'irclid',
  '_kx',
] as const;

const FALLBACK_ORIGIN = 'https://bite-worthy.com';

export function isSensitiveParam(key: string): boolean {
  const lower = key.toLowerCase();
  if (
    (SENSITIVE_PARAMS as readonly string[]).includes(lower) ||
    (TRACKING_PARAMS as readonly string[]).includes(lower) ||
    lower.startsWith('utm_')
  ) {
    return true;
  }
  return lower.endsWith('_token') || lower.endsWith('_key');
}

/**
 * Strip sensitive and tracking params from a URL string (query + hash).
 * Path and non-sensitive params are left intact.
 */
export function sanitizeUrl(url: string): string {
  if (url === '') return url;
  try {
    const base = typeof window !== 'undefined' ? window.location.origin : FALLBACK_ORIGIN;
    const parsed = new URL(url, base);
    sanitizeSearchParams(parsed.searchParams);
    // Hash fragments can also carry params: `#activate=code&email=user@example.com`
    if (parsed.hash.includes('=')) {
      const hashParams = new URLSearchParams(parsed.hash.slice(1));
      sanitizeSearchParams(hashParams);
      parsed.hash = hashParams.toString();
    }
    return parsed.toString();
  } catch {
    return url;
  }
}

/** Same rule as `sanitizeUrl`, named for referrer / `rl` coverage in tests. */
export function sanitizeReferrer(url: string): string {
  return sanitizeUrl(url);
}

/**
 * Drop sensitive keys from an event-param object and sanitize any
 * URL-like values so a caller cannot leak a token through a pixel event.
 */
export function sanitizeEventParams(params: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(params)) {
    if (isSensitiveParam(key)) continue;
    if (typeof value === 'string' && looksLikeUrl(value)) {
      out[key] = sanitizeUrl(value);
    } else {
      out[key] = value;
    }
  }
  return out;
}

function looksLikeUrl(value: string): boolean {
  return (
    value.startsWith('http://') ||
    value.startsWith('https://') ||
    value.startsWith('/') ||
    value.startsWith('#')
  );
}

function sanitizeSearchParams(params: URLSearchParams): void {
  const keysToDelete: string[] = [];
  params.forEach((_value, key) => {
    if (isSensitiveParam(key)) keysToDelete.push(key);
  });
  for (const key of keysToDelete) params.delete(key);
}

/**
 * Sanitize the current page URL in place via `history.replaceState`.
 * Call this BEFORE any Meta Pixel request (or any tracker that
 * auto-collects `document.location`). Idempotent.
 *
 * The restaurant page already consumed `?p=` / `?profile=` at SSR and
 * holds them in props, so stripping them from the address bar does not
 * change the applied filter. A later full reload of the cleaned URL
 * would, which is the same trade the invalid-token cleanup already made.
 */
export function sanitizeCurrentUrl(): void {
  if (typeof window === 'undefined' || typeof history === 'undefined') return;
  const original = window.location.href;
  const sanitized = sanitizeUrl(original);
  if (sanitized !== original) {
    history.replaceState(history.state, '', sanitized);
  }
}

/**
 * Standalone snippet that applies the same redaction rule, meant to be
 * the first statements of any inline analytics bootstrap so `init` /
 * PageView never races a React effect. Kept in lockstep with
 * `SENSITIVE_PARAMS` via `JSON.stringify` of the shared arrays.
 *
 * The live Pixel does not load `fbevents.js`, so this snippet is not
 * injected today. It exists so a future bootstrap cannot drift from
 * the TypeScript sanitizer.
 */
export function inlineUrlSanitizerSnippet(): string {
  const names = JSON.stringify([...SENSITIVE_PARAMS, ...TRACKING_PARAMS]);
  return `(function(){try{var N=${names};function d(k){k=String(k).toLowerCase();if(N.indexOf(k)!==-1)return true;if(k.slice(0,4)==='utm_')return true;return k.slice(-6)==='_token'||k.slice(-4)==='_key'}function c(sp){var ks=[];sp.forEach(function(_v,k){if(d(k))ks.push(k)});for(var i=0;i<ks.length;i++)sp.delete(ks[i])}var u=new URL(location.href);c(u.searchParams);if(u.hash.indexOf('=')!==-1){var h=new URLSearchParams(u.hash.slice(1));c(h);u.hash=h.toString()}if(u.href!==location.href)history.replaceState(history.state,'',u.href)}catch(e){}})();`;
}
