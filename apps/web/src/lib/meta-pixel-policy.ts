/**
 * What the Meta Pixel may tell Meta. The site does not load Meta's script;
 * `lib/meta-pixel.ts` sends the pixel's image requests itself, built only
 * from what this module allows, so this file is the whole of what Meta
 * can learn, and the privacy policy describes exactly this rule.
 *
 * Pages: an allowlist, so a new page is excluded until someone decides
 * otherwise. Pages that can reveal a diet, a person, or an account (diet
 * pages, /u/<handle>, history, chat, onboarding, settings, admin, adding
 * a restaurant, menu scans, suggestions, claims) never match.
 *
 * Addresses: only the path is ever sent. Nothing after "?" or "#" leaves
 * the browser, because restaurant links carry the chosen diet as
 * `?profile=celiac` and shared filters as `?p=`.
 */
const EXACT = new Set(['/', '/signup', '/story', '/press', '/updates', '/durango', '/restaurants']);

// /restaurants/<country>[/<region>[/<city>[/<restaurant>[/items/<dish>]]]],
// and never /restaurants/new.
const RESTAURANT_PAGE =
  /^\/restaurants\/(?!new$)[^/]+(?:\/[^/]+(?:\/[^/]+(?:\/[^/]+(?:\/items\/[^/]+)?)?)?)?$/;

export function metaPixelPathAllowed(pathname: string): boolean {
  return EXACT.has(pathname) || RESTAURANT_PAGE.test(pathname);
}

/** The page address Meta receives: origin and path, nothing after it. */
export function metaPageAddress(origin: string, pathname: string): string {
  return `${origin}${pathname}`;
}

/**
 * The referrer Meta receives. Our own pages: the path, and only when that
 * path is itself allowed (otherwise just the origin). Other sites: their
 * origin only.
 */
export function metaReferrer(referrer: string, origin: string): string {
  if (referrer === '') return '';
  let url: URL;
  try {
    url = new URL(referrer);
  } catch {
    return '';
  }
  if (url.origin === origin && metaPixelPathAllowed(url.pathname)) {
    return metaPageAddress(url.origin, url.pathname);
  }
  return url.origin;
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
