/**
 * WBW-173 — sanitize URLs before third-party analytics sees them.
 *
 * Share links (`/r/<slug>?p=<token>`) encode the sharer's avoid-list IDs
 * and strictness. Diet-page links carry `?profile=celiac`. Meta's pixel
 * used to auto-collect `document.location` (dl) and `document.referrer`
 * (rl) on every event, which sent those values to Meta. The site no
 * longer loads `fbevents.js` (see `lib/meta-pixel.ts`); this sanitizer
 * is the common rule for (1) the outbound pixel request URL and (2) any
 * URL-like event params. It must not rewrite `window.location`: a
 * reload, and the claim/login `next=` bounce that rebuilds from
 * `location.search`, both need `?p=` / `?profile=` to keep applying
 * the shared filter.
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
