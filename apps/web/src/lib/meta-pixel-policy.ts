/**
 * Where the Meta Pixel may fire. Meta receives the page's full address
 * with every event, so this decides what Meta can learn, and the privacy
 * policy describes exactly this rule.
 *
 * An allowlist, so a new page is excluded until someone decides otherwise.
 * Pages that can reveal a diet, a person, or an account (diet pages,
 * /u/<handle>, history, chat, onboarding, settings, admin) never match.
 * Any address with a query string is refused too: restaurant links carry
 * the chosen diet as `?profile=celiac` and shared filters as `?p=`.
 */
const EXACT = new Set(['/', '/signup', '/login', '/story', '/press', '/updates', '/durango']);
const PREFIXES = ['/restaurants'];

export function metaPixelPathAllowed(pathname: string, search: string): boolean {
  if (search !== '' && search !== '?') return false;
  if (EXACT.has(pathname)) return true;
  return PREFIXES.some((p) => pathname === p || pathname.startsWith(`${p}/`));
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
