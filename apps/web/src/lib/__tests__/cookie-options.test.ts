import { describe, expect, it } from 'vitest';
import { buildAuthCookieOptions } from '../cookie-options';

describe('buildAuthCookieOptions', () => {
  it('emits the canonical secure-cookie shape (httpOnly + sameSite=lax + path=/)', () => {
    const opts = buildAuthCookieOptions('bw_session', 'jwt-value', 1234, {
      production: true,
      domain: null,
    });
    expect(opts).toEqual({
      name: 'bw_session',
      value: 'jwt-value',
      httpOnly: true,
      secure: true,
      sameSite: 'lax',
      path: '/',
      maxAge: 1234,
    });
  });

  it('omits the domain attribute when not configured (dev / localhost)', () => {
    const opts = buildAuthCookieOptions('bw_session', 'tok', 30, {
      production: false,
      domain: null,
    });
    expect(opts.domain).toBeUndefined();
    expect(opts.secure).toBe(false);
  });

  it('attaches domain when NEXT_PUBLIC_COOKIE_DOMAIN-style override is provided (production)', () => {
    const opts = buildAuthCookieOptions('bw_session', 'tok', 30, {
      production: true,
      domain: '.bite-worthy.com',
    });
    expect(opts.domain).toBe('.bite-worthy.com');
  });

  it('clears the cookie correctly when maxAge is 0 (logout path)', () => {
    const opts = buildAuthCookieOptions('bw_session', '', 0, {
      production: true,
      domain: '.bite-worthy.com',
    });
    expect(opts.value).toBe('');
    expect(opts.maxAge).toBe(0);
    expect(opts.domain).toBe('.bite-worthy.com');
  });

  it('reads NEXT_PUBLIC_COOKIE_DOMAIN from env when no override is given', () => {
    const original = process.env.NEXT_PUBLIC_COOKIE_DOMAIN;
    process.env.NEXT_PUBLIC_COOKIE_DOMAIN = '.bite-worthy.com';
    try {
      const opts = buildAuthCookieOptions('bw_session', 'tok', 30, { production: true });
      expect(opts.domain).toBe('.bite-worthy.com');
    } finally {
      if (original === undefined) delete process.env.NEXT_PUBLIC_COOKIE_DOMAIN;
      else process.env.NEXT_PUBLIC_COOKIE_DOMAIN = original;
    }
  });
});
