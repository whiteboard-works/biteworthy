/**
 * WBW-173 — sanitize URLs before third-party analytics sees them.
 *
 * Meta Pixel auto-collects `dl` (document.location) and `rl`
 * (document.referrer) on every event, including private share tokens
 * (`?p=<token>` encodes the sharer's avoid-list IDs + strictness) and
 * other sensitive params (license keys, activation codes, transaction
 * IDs, emails). This sanitizer strips those params from both query
 * strings AND hash fragments.
 *
 * Approach (see `_MetaPixelProvider` for how it is applied):
 *   1. `history.replaceState` rewrites `document.location` in place
 *      BEFORE `fbq('init')` / PageView, so the auto-collected `dl` is
 *      already clean. There is no supported fbq API to override `dl`.
 *   2. `document.referrer` is read-only — we sanitize any referrer we
 *      ourselves pass as an event param, but we cannot change what
 *      the browser reports as `rl` on the first hit.
 *
 * Sensitive params (removed from both `?query` and `#hash`):
 *   - `p`, `token`, `*_token` — share/auth tokens
 *   - `key`, `*_key`, `license_key` — API/license keys
 *   - `transaction_id`, `email`, `code`, `activate`, `note`, `source_url`
 */

export const SENSITIVE_PARAMS = [
  'p',
  'token',
  'key',
  'license_key',
  'transaction_id',
  'email',
  'activate',
  'code',
  'note',
  'source_url',
] as const;

// Marketing/tracking params PostHog already strips — keep both trackers consistent.
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
    (TRACKING_PARAMS as readonly string[]).includes(lower)
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
 * URL-like values so a future caller cannot leak a token through
 * `trackMetaEvent`.
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
 * Call this BEFORE initializing Meta Pixel (or any tracker that
 * auto-collects `document.location`). Idempotent.
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
 * the first statements of the Meta Pixel inline bootstrap so `fbq('init')`
 * never races a React effect. Kept in lockstep with `SENSITIVE_PARAMS`
 * via `JSON.stringify` of the shared arrays.
 */
export function inlineUrlSanitizerSnippet(): string {
  const names = JSON.stringify([...SENSITIVE_PARAMS, ...TRACKING_PARAMS]);
  return `(function(){try{var N=${names};function d(k){k=String(k).toLowerCase();if(N.indexOf(k)!==-1)return true;return k.slice(-6)==='_token'||k.slice(-4)==='_key'}function c(sp){var ks=[];sp.forEach(function(_v,k){if(d(k))ks.push(k)});for(var i=0;i<ks.length;i++)sp.delete(ks[i])}var u=new URL(location.href);c(u.searchParams);if(u.hash.indexOf('=')!==-1){var h=new URLSearchParams(u.hash.slice(1));c(h);u.hash=h.toString()}if(u.href!==location.href)history.replaceState(history.state,'',u.href)}catch(e){}})();`;
}
