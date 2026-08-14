/**
 * Sanitises a `?next=` destination before it reaches `router.replace`.
 *
 * `/login` and `/signup` bounce to whatever `?next=` holds, and half a
 * dozen pages mint those links (`_ChatClient`, `RestaurantClient`,
 * `/profile/settings`, the consent screen, …). Unvalidated, that is an
 * open redirect: Next's `navigateReducer` checks
 * `url.origin !== location.origin` and hands anything cross-origin to a
 * full-page navigation, so `?next=https://evil.com` lands a successful
 * login on someone else's site.
 *
 * **A `startsWith('/')` check is not enough**, which is the whole reason
 * this is a function and not an inline guard. WHATWG URL parsing
 * normalises a backslash to a slash for special schemes, so `/\evil.com`
 * and `/\/evil.com` both start with `/` and both resolve to
 * `https://evil.com`. Prefix matching cannot see that; origin comparison
 * can.
 *
 * Resolved against a sentinel base rather than `window.location.origin`
 * so the answer does not depend on the browser: these pages render on
 * the server too, and a guard that returns the fallback during SSR and
 * the real path after hydration is a hydration mismatch. The sentinel
 * cannot be the real origin, so an absolute URL — even our own — is
 * refused and only paths survive. Every producer emits a path.
 */
const BASE = 'https://redirect.invalid';

export function safeNext(raw: string | null | undefined, fallback: string): string {
  if (!raw) return fallback;

  let url: URL;
  try {
    url = new URL(raw, BASE);
  } catch {
    return fallback;
  }
  if (url.origin !== BASE) return fallback;

  return `${url.pathname}${url.search}${url.hash}`;
}
