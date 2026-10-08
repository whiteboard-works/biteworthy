import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  SENSITIVE_PARAMS,
  inlineUrlSanitizerSnippet,
  sanitizeCurrentUrl,
  sanitizeEventParams,
  sanitizeReferrer,
  sanitizeUrl,
} from '../sanitize-url';

/**
 * The Pixel sends whatever is in document.location / document.referrer /
 * event params. These cases exist so a share token (`?p=`), a license
 * key, an email, or `#activate=&email=` cannot reach Meta.
 */
describe('sanitizeUrl', () => {
  describe('query string params', () => {
    it('strips the share token param (dietary profile in ?p=)', () => {
      const url =
        'https://example.com/r/cafe-delicious?p=eyJ2IjoyLCJhaSI6W10sImF0IjpbXSwicyI6ImNhc3VhbCIsImV4cCI6MTczMDAwMDAwMH0';
      expect(sanitizeUrl(url)).toBe('https://example.com/r/cafe-delicious');
    });

    it('strips token params', () => {
      expect(sanitizeUrl('https://example.com/reset-password?token=abc123')).toBe(
        'https://example.com/reset-password',
      );
    });

    it('strips params ending in _token', () => {
      expect(sanitizeUrl('https://example.com/verify?reset_token=xyz')).toBe(
        'https://example.com/verify',
      );
      expect(sanitizeUrl('https://example.com/oauth?access_token=bearer123')).toBe(
        'https://example.com/oauth',
      );
    });

    it('strips key and license_key params', () => {
      expect(sanitizeUrl('https://example.com/activate?key=abc')).toBe(
        'https://example.com/activate',
      );
      expect(sanitizeUrl('https://example.com/activate?license_key=PRO-123')).toBe(
        'https://example.com/activate',
      );
    });

    it('strips params ending in _key', () => {
      expect(sanitizeUrl('https://example.com/api?api_key=secret')).toBe('https://example.com/api');
      expect(sanitizeUrl('https://example.com/setup?activation_key=xyz')).toBe(
        'https://example.com/setup',
      );
    });

    it('strips email params', () => {
      expect(sanitizeUrl('https://example.com/signup?email=user@example.com')).toBe(
        'https://example.com/signup',
      );
    });

    it('strips transaction_id params', () => {
      expect(sanitizeUrl('https://example.com/success?transaction_id=tx_123456')).toBe(
        'https://example.com/success',
      );
    });

    it('strips activate and code params', () => {
      expect(sanitizeUrl('https://example.com/welcome?activate=code123')).toBe(
        'https://example.com/welcome',
      );
      expect(sanitizeUrl('https://example.com/verify?code=ABC123')).toBe(
        'https://example.com/verify',
      );
    });

    it('strips note and source_url params', () => {
      expect(
        sanitizeUrl('https://example.com/feedback?note=private-comment&source_url=internal'),
      ).toBe('https://example.com/feedback');
    });

    it('strips tracking params (utm_*, gclid, fbclid, etc.)', () => {
      const url =
        'https://example.com/landing?utm_source=google&utm_medium=cpc&utm_campaign=fall&gclid=abc&fbclid=xyz';
      expect(sanitizeUrl(url)).toBe('https://example.com/landing');
    });

    it('preserves non-sensitive params', () => {
      const url = 'https://example.com/search?q=tacos&filter=vegan&sort=rating';
      expect(sanitizeUrl(url)).toBe(url);
    });

    it('strips sensitive params and preserves safe ones', () => {
      const url = 'https://example.com/r/cafe?p=token123&view=menu&section=appetizers';
      const sanitized = sanitizeUrl(url);
      expect(sanitized).toContain('view=menu');
      expect(sanitized).toContain('section=appetizers');
      expect(sanitized).not.toContain('p=');
    });

    it('is case-insensitive for param names', () => {
      expect(sanitizeUrl('https://example.com/page?P=token123&EMAIL=test@example.com')).toBe(
        'https://example.com/page',
      );
    });
  });

  describe('hash fragment params', () => {
    it('strips activation codes and emails from hash fragments', () => {
      const url = 'https://example.com/activate#activate=code123&email=user@example.com';
      expect(sanitizeUrl(url)).toBe('https://example.com/activate');
    });

    it('strips token and license_key from hash', () => {
      expect(sanitizeUrl('https://example.com/app#access_token=bearer123')).toBe(
        'https://example.com/app',
      );
      expect(sanitizeUrl('https://example.com/setup#license_key=PRO-456')).toBe(
        'https://example.com/setup',
      );
    });

    it('preserves safe hash params', () => {
      const url = 'https://example.com/docs#section=intro&page=2';
      expect(sanitizeUrl(url)).toBe(url);
    });

    it('strips sensitive hash params and preserves safe ones', () => {
      const url = 'https://example.com/app#view=dashboard&token=secret123';
      const sanitized = sanitizeUrl(url);
      expect(sanitized).toContain('view=dashboard');
      expect(sanitized).not.toContain('token=');
    });

    it('leaves non-param hashes unchanged', () => {
      expect(sanitizeUrl('https://example.com/docs#introduction')).toBe(
        'https://example.com/docs#introduction',
      );
    });
  });

  describe('combined query and hash', () => {
    it('strips sensitive params from both query and hash', () => {
      const url =
        'https://example.com/activate?license_key=abc#activate=xyz&email=test@example.com';
      expect(sanitizeUrl(url)).toBe('https://example.com/activate');
    });

    it('preserves safe params in both query and hash', () => {
      const url = 'https://example.com/search?q=tacos#results';
      expect(sanitizeUrl(url)).toBe(url);
    });
  });

  describe('edge cases', () => {
    it('handles URLs without query or hash', () => {
      const url = 'https://example.com/path/to/page';
      expect(sanitizeUrl(url)).toBe(url);
    });

    it('handles relative URLs', () => {
      const url = '/r/cafe?p=token123';
      const sanitized = sanitizeUrl(url);
      expect(sanitized).toContain('/r/cafe');
      expect(sanitized).not.toContain('p=');
    });

    it('returns unparseable URLs unchanged', () => {
      expect(sanitizeUrl('http://[')).toBe('http://[');
    });
  });

  describe('real-world BiteWorthy URLs', () => {
    it('sanitizes a shared menu link with profile token', () => {
      const url =
        'https://bite-worthy.com/r/downtown-cafe?p=eyJ2IjoyLCJhaSI6WyJkYWlyeSIsImVnZ3MiXSwiYXQiOltdLCJzIjoic3RyaWN0IiwiZXhwIjoxNzMwMDAwMDAwfQ';
      expect(sanitizeUrl(url)).toBe('https://bite-worthy.com/r/downtown-cafe');
    });

    it('sanitizes password reset link', () => {
      expect(sanitizeUrl('https://bite-worthy.com/reset-password?token=abc123xyz')).toBe(
        'https://bite-worthy.com/reset-password',
      );
    });

    it('sanitizes OAuth callback code and keeps state', () => {
      const sanitized = sanitizeUrl(
        'https://bite-worthy.com/oauth/callback?code=auth123&state=xyz',
      );
      expect(sanitized).not.toContain('code=');
      expect(sanitized).toContain('state=xyz');
    });
  });
});

describe('sanitizeReferrer (what the Pixel would send as rl)', () => {
  it('strips tokens, keys, emails, transaction IDs, activation codes and notes', () => {
    const dirty =
      'https://referrer.example/done?token=t&license_key=k&email=a@b.c&transaction_id=tx&activate=z&note=secret';
    const clean = sanitizeReferrer(dirty);
    expect(clean).toBe('https://referrer.example/done');
  });

  it('strips hash-fragment activation payloads on a referrer', () => {
    expect(sanitizeReferrer('https://referrer.example/#activate=code&email=a@b.c')).toBe(
      'https://referrer.example/',
    );
  });

  it('keeps non-sensitive referrer params', () => {
    const url = 'https://referrer.example/from?utm_campaign=drop-me&q=tacos';
    const clean = sanitizeReferrer(url);
    expect(clean).toContain('q=tacos');
    expect(clean).not.toContain('utm_campaign');
  });
});

describe('sanitizeEventParams (what the Pixel would send as custom data)', () => {
  it('drops sensitive keys rather than sending them to Meta', () => {
    expect(
      sanitizeEventParams({
        email: 'user@example.com',
        token: 'abc',
        license_key: 'PRO-1',
        transaction_id: 'tx_9',
        activate: 'code',
        note: 'private',
        content_name: 'BiteWorthy',
      }),
    ).toEqual({ content_name: 'BiteWorthy' });
  });

  it('sanitizes URL-like values including hash fragments', () => {
    const out = sanitizeEventParams({
      page_url: 'https://bite-worthy.com/r/cafe?p=secret#activate=z&email=a@b.c',
      path: '/reset-password?token=abc',
      value: 1,
    });
    expect(out['page_url']).toBe('https://bite-worthy.com/r/cafe');
    expect(String(out['path'])).toContain('/reset-password');
    expect(String(out['path'])).not.toContain('token=');
    expect(out['value']).toBe(1);
  });
});

describe('inlineUrlSanitizerSnippet', () => {
  it('embeds every sensitive param name so the bootstrap cannot drift', () => {
    const snippet = inlineUrlSanitizerSnippet();
    for (const name of SENSITIVE_PARAMS) {
      expect(snippet).toContain(`"${name}"`);
    }
  });

  it('strips a share token from location before any later fbq call would read it', () => {
    const original = window.location.href;
    history.replaceState(history.state, '', `${window.location.origin}/r/cafe?p=secret&view=menu`);
    // eslint-disable-next-line no-eval
    eval(inlineUrlSanitizerSnippet());
    expect(window.location.search).not.toContain('p=');
    expect(window.location.search).toContain('view=menu');
    history.replaceState(history.state, '', original);
  });
});

describe('sanitizeCurrentUrl', () => {
  let replaceStateSpy: ReturnType<typeof vi.spyOn>;
  let originalHref: string;

  beforeEach(() => {
    replaceStateSpy = vi.spyOn(history, 'replaceState');
    originalHref = window.location.href;
  });

  afterEach(() => {
    replaceStateSpy.mockRestore();
    if (window.location.href !== originalHref) {
      history.replaceState(history.state, '', originalHref);
    }
  });

  it('calls history.replaceState when sensitive params exist', () => {
    const testUrl = `${window.location.origin}/test?p=token123`;
    history.replaceState(history.state, '', testUrl);
    replaceStateSpy.mockClear();

    sanitizeCurrentUrl();

    expect(replaceStateSpy).toHaveBeenCalledOnce();
    expect(String(replaceStateSpy.mock.calls[0]?.[2])).not.toContain('p=');
  });

  it('does not call history.replaceState when URL is already clean', () => {
    const cleanUrl = `${window.location.origin}/test?safe=param`;
    history.replaceState(history.state, '', cleanUrl);
    replaceStateSpy.mockClear();

    sanitizeCurrentUrl();

    expect(replaceStateSpy).not.toHaveBeenCalled();
  });

  it('is idempotent', () => {
    const testUrl = `${window.location.origin}/test?p=token123`;
    history.replaceState(history.state, '', testUrl);
    replaceStateSpy.mockClear();

    sanitizeCurrentUrl();
    expect(replaceStateSpy).toHaveBeenCalledOnce();

    replaceStateSpy.mockClear();
    sanitizeCurrentUrl();
    expect(replaceStateSpy).not.toHaveBeenCalled();
  });
});
