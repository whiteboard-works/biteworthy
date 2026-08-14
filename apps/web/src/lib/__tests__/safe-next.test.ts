import { describe, it, expect } from 'vitest';
import { safeNext } from '../safe-next';

describe('safeNext', () => {
  it('keeps an ordinary in-app path', () => {
    expect(safeNext('/history', '/')).toBe('/history');
  });

  it('preserves the query string and hash', () => {
    expect(safeNext('/restaurants/ninis?diet=vegan#menu', '/')).toBe(
      '/restaurants/ninis?diet=vegan#menu',
    );
  });

  it('falls back when there is no destination', () => {
    expect(safeNext(null, '/onboarding')).toBe('/onboarding');
    expect(safeNext(undefined, '/')).toBe('/');
    expect(safeNext('', '/')).toBe('/');
  });

  it('refuses an absolute URL to another site', () => {
    expect(safeNext('https://evil.com', '/')).toBe('/');
  });

  it('refuses a protocol-relative URL', () => {
    expect(safeNext('//evil.com', '/')).toBe('/');
    expect(safeNext('////evil.com', '/')).toBe('/');
  });

  // The case a `startsWith('/')` guard lets through, and the reason this
  // is an origin check rather than a prefix check: WHATWG URL parsing
  // normalises `\` to `/` for special schemes, so both of these begin
  // with a slash and both resolve to https://evil.com.
  it('refuses a backslash-smuggled host that still starts with a slash', () => {
    expect(safeNext('/\\evil.com', '/')).toBe('/');
    expect(safeNext('/\\/evil.com', '/')).toBe('/');
    expect(safeNext('\\/\\/evil.com', '/')).toBe('/');
  });

  // These resolve to the sentinel origin — so an input-only origin check
  // passes them — and then *serialise* to the pathname `//evil.com`,
  // which the router parses as protocol-relative and follows off-site.
  // The guard re-resolves the value it is about to return for this case.
  it('refuses a dot-segment path that normalises into a protocol-relative one', () => {
    expect(safeNext('.//evil.com', '/')).toBe('/');
    expect(safeNext('/a/..//evil.com', '/')).toBe('/');
    expect(safeNext('/./..//evil.com', '/')).toBe('/');
  });

  // Dot segments that resolve to a real in-app path still work. The guard
  // rejects the escape, not the notation.
  it('keeps a dot-segment path that stays in-app', () => {
    expect(safeNext('/restaurants/../history', '/')).toBe('/history');
  });

  it('refuses a non-http scheme', () => {
    expect(safeNext('javascript:alert(1)', '/')).toBe('/');
    expect(safeNext('data:text/html,<script>alert(1)</script>', '/')).toBe('/');
  });

  // Our own origin spelled absolutely is refused too. Nothing produces
  // one, and accepting it would mean the guard's answer depended on which
  // host it ran under — the dependency the sentinel base exists to remove.
  it('refuses an absolute URL even to our own site', () => {
    expect(safeNext('https://bite-worthy.com/history', '/')).toBe('/');
  });

  // Percent-encoded slashes are a path segment, not a host — browsers do
  // not re-decode them into an authority, so this stays in-app.
  it('leaves percent-encoded slashes as a path', () => {
    expect(safeNext('/%2f%2fevil.com', '/')).toBe('/%2f%2fevil.com');
  });
});
