/**
 * Where the Meta Pixel may fire. Meta receives the page's full address
 * (`dl`) and the address of the page before it (`rl`) with every event, so
 * this decides what Meta can learn, and the privacy policy describes
 * exactly this rule.
 *
 * An allowlist, so a new page is excluded until someone decides otherwise.
 * Pages that can reveal a diet, a person, or an account (diet pages,
 * /u/<handle>, history, chat, onboarding, settings, admin, adding a
 * restaurant, menu scans, suggestions, claims) never match. Sign-in and
 * sign-up pages are out too, because they hold email fields and Meta's
 * automatic advanced matching can read those.
 *
 * Any address with something after "?" or "#" is refused, because
 * restaurant links carry the chosen diet as `?profile=celiac` and shared
 * filters as `?p=`.
 */
const EXACT = new Set(['/', '/story', '/press', '/updates', '/durango', '/restaurants']);

// /restaurants/<country>[/<region>[/<city>[/<restaurant>[/items/<dish>]]]],
// and never /restaurants/new.
const RESTAURANT_PAGE =
  /^\/restaurants\/(?!new$)[^/]+(?:\/[^/]+(?:\/[^/]+(?:\/[^/]+(?:\/items\/[^/]+)?)?)?)?$/;

type Where = Pick<URL, 'pathname' | 'search' | 'hash'>;

export function metaPixelUrlAllowed({ pathname, search, hash }: Where): boolean {
  if (search !== '' && search !== '?') return false;
  if (hash !== '' && hash !== '#') return false;
  return EXACT.has(pathname) || RESTAURANT_PAGE.test(pathname);
}

/**
 * The referrer rides along with every event. A visitor who comes to an
 * allowed page from `/restaurants/…?profile=celiac` would otherwise hand
 * Meta that address. Another site's address is not ours to reveal.
 */
export function metaPixelReferrerAllowed(referrer: string, origin: string): boolean {
  if (referrer === '') return true;
  let url: URL;
  try {
    url = new URL(referrer);
  } catch {
    return false;
  }
  if (url.origin !== origin) return true;
  return metaPixelUrlAllowed(url);
}

/**
 * Global Privacy Control is the browser's "do not sell or share" signal.
 * Sending page activity to Meta for ads is sharing under California law,
 * so it switches the pixel off on its own.
 */
export function globalPrivacyControl(): boolean {
  if (typeof navigator === 'undefined') return false;
  return (navigator as { globalPrivacyControl?: boolean }).globalPrivacyControl === true;
}
