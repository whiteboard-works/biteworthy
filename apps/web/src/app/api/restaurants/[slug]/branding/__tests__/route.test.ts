import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

/**
 * The branding proxy relays the multipart body byte-for-byte with its
 * boundary header — re-encoding it would corrupt the upload — and never
 * reaches Rails without a session.
 */

const mockGetServerJwt = vi.fn();
vi.mock('../../../../../../lib/server-auth', () => ({
  getServerJwt: () => mockGetServerJwt(),
}));
vi.mock('../../../../../../lib/edge-headers', () => ({
  edgeHeaders: async () => ({}),
}));

import { PATCH } from '../route';

beforeEach(() => {
  vi.restoreAllMocks();
  mockGetServerJwt.mockReset();
});

const params = Promise.resolve({ slug: 'ninis' });

describe('PATCH /api/restaurants/:slug/branding', () => {
  it('relays the multipart body and content type with the bearer token', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    const spy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      status: 200,
      text: async () => '{"logo_url":"x"}',
      headers: { get: () => 'application/json' },
    } as unknown as Response);

    const req = new NextRequest('http://localhost/api/restaurants/ninis/branding', {
      method: 'PATCH',
      headers: { 'Content-Type': 'multipart/form-data; boundary=abc' },
      body: '--abc--',
    });
    const res = await PATCH(req, { params });

    const [url, init] = spy.mock.calls[0]! as [
      string,
      { method: string; headers: Record<string, string>; body: ArrayBuffer },
    ];
    expect(String(url)).toContain('/api/v1/restaurants/ninis/branding');
    expect(init.method).toBe('PATCH');
    expect(init.headers.Authorization).toBe('Bearer jwt-1');
    expect(init.headers['Content-Type']).toBe('multipart/form-data; boundary=abc');
    expect(new TextDecoder().decode(init.body)).toBe('--abc--');
    expect(res.status).toBe(200);
    expect(res.headers.get('Cache-Control')).toBe('no-store');
  });

  it('401s locally when signed out', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    const spy = vi.spyOn(globalThis, 'fetch');
    const req = new NextRequest('http://localhost/api/restaurants/ninis/branding', {
      method: 'PATCH',
      body: '--abc--',
    });
    const res = await PATCH(req, { params });
    expect(res.status).toBe(401);
    expect(spy).not.toHaveBeenCalled();
  });
});
