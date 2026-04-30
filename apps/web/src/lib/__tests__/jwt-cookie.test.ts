import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { clearJwtCookie, getJwtCookie, setJwtCookie } from '../jwt-cookie';

// vitest defaults to node env — stub the DOM bits the helper touches.
let cookieJar = '';

beforeEach(() => {
  cookieJar = '';
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      get cookie() {
        return cookieJar;
      },
      set cookie(value: string) {
        // Document.cookie semantics: each set adds (or overwrites by name).
        // Crude but enough for these tests — split off the name=value head.
        const head = value.split(';')[0]!;
        const [name] = head.split('=');
        const parts = cookieJar
          ? cookieJar.split('; ').filter((p) => !p.startsWith(`${name}=`))
          : [];

        // Detect Max-Age=0 (deletion) by sniffing the rest of the value.
        if (/Max-Age=0\b/.test(value)) {
          cookieJar = parts.join('; ');
          return;
        }
        parts.push(head);
        cookieJar = parts.join('; ');
      },
    },
  });
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: { location: { protocol: 'http:' } },
  });
});

afterEach(() => {
  // @ts-expect-error — cleanup the stubbed globals
  delete globalThis.document;
  // @ts-expect-error — cleanup the stubbed globals
  delete globalThis.window;
});

describe('jwt-cookie helpers', () => {
  it('round-trips a JWT through set + get', () => {
    setJwtCookie('header.payload.sig');
    expect(getJwtCookie()).toBe('header.payload.sig');
  });

  it('returns null when no cookie is set', () => {
    expect(getJwtCookie()).toBeNull();
  });

  it('clears the cookie', () => {
    setJwtCookie('jjj');
    clearJwtCookie();
    expect(getJwtCookie()).toBeNull();
  });

  it('encodes/decodes values that contain reserved characters', () => {
    const tricky = 'header.payload.with spaces & =equals=';
    setJwtCookie(tricky);
    expect(getJwtCookie()).toBe(tricky);
  });

  it('returns null safely in a non-DOM environment', () => {
    // @ts-expect-error — simulate SSR / node environment
    delete globalThis.document;
    expect(getJwtCookie()).toBeNull();
  });
});
