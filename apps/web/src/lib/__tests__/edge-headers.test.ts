import { afterEach, describe, expect, it, vi } from 'vitest';

/**
 * Rails throttles anonymous web traffic by the IP this forwards, and only
 * believes it alongside the shared secret — so without the secret nothing
 * may be sent, and the secret must only ever travel with a real client IP.
 */

// A plain swappable function, not vi.fn: this vitest reports any throw that
// passes through a vi.fn as a failure, even one the caller catches.
let headersImpl: () => unknown = () => ({ get: () => null });
vi.mock('next/headers', () => ({ headers: () => headersImpl() }));

const { edgeHeaders } = await import('../edge-headers');

function outsideRequest(): never {
  throw new Error('headers() outside a request scope');
}

const incoming = (h: Record<string, string>) => ({
  get: (k: string) => h[k.toLowerCase()] ?? null,
});

describe('edgeHeaders', () => {
  afterEach(() => vi.unstubAllEnvs());

  it('sends nothing until the proxy secret is configured', async () => {
    vi.stubEnv('WEB_PROXY_SECRET', '');
    headersImpl = () => incoming({ 'x-forwarded-for': '203.0.113.7' });
    expect(await edgeHeaders()).toEqual({});
  });

  it("forwards the visitor's own IP, first in the forwarded chain", async () => {
    vi.stubEnv('WEB_PROXY_SECRET', 's3cret');
    headersImpl = () => incoming({ 'x-forwarded-for': '203.0.113.7, 10.0.0.1' });
    expect(await edgeHeaders()).toEqual({
      'X-BW-Client-IP': '203.0.113.7',
      'X-BW-Proxy-Secret': 's3cret',
    });
  });

  it('sends nothing outside a request (build, ISR revalidation)', async () => {
    vi.stubEnv('WEB_PROXY_SECRET', 's3cret');
    headersImpl = outsideRequest;
    expect(await edgeHeaders()).toEqual({});
  });

  it('sends nothing when no client IP is known', async () => {
    vi.stubEnv('WEB_PROXY_SECRET', 's3cret');
    headersImpl = () => incoming({});
    expect(await edgeHeaders()).toEqual({});
  });
});
