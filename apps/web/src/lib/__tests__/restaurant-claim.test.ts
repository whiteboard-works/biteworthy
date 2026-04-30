import { describe, expect, it, vi } from 'vitest';
import {
  ClaimError,
  requestClaim,
  verifyClaim,
} from '../restaurant-claim';

type FetchArgs = Parameters<typeof fetch>;

function fakeFetch(status: number, body: unknown) {
  return vi.fn(
    async (..._args: FetchArgs) =>
      ({
        ok: status >= 200 && status < 300,
        status,
        statusText: status === 200 ? 'OK' : 'ERR',
        json: async () => body,
      }) as unknown as Response,
  );
}

describe('requestClaim', () => {
  it('POSTs JSON to the Next proxy with credentials (no client-side Authorization)', async () => {
    const fetchImpl = fakeFetch(202, {
      status: 'verification_sent',
      email: 'owner@x.com',
      auto_acceptable: true,
      expires_at: '2026-05-07T00:00:00Z',
    });
    const out = await requestClaim('cream-bean-berry-1', 'owner@x.com', { fetchImpl });
    expect(out.status).toBe('verification_sent');

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/restaurants/cream-bean-berry-1/claim');
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
    expect(JSON.parse(init.body as string)).toEqual({ email: 'owner@x.com' });
  });

  it('throws ClaimError carrying status (so a 401 caller can bounce to /login)', async () => {
    const fetchImpl = fakeFetch(401, { error: 'Not signed in' });
    await expect(requestClaim('s', 'a@b.com', { fetchImpl })).rejects.toMatchObject({
      name: 'ClaimError',
      status: 401,
    });
  });

  it('preserves the API error kind on 422 (e.g. AlreadyClaimed)', async () => {
    const fetchImpl = fakeFetch(409, { error: 'already claimed', kind: 'AlreadyClaimedError' });
    try {
      await requestClaim('s', 'a@b.com', { fetchImpl });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e).toBeInstanceOf(ClaimError);
      expect((e as ClaimError).kind).toBe('AlreadyClaimedError');
    }
  });
});

describe('verifyClaim', () => {
  it('GETs the verify endpoint with the token in the query string', async () => {
    const fetchImpl = fakeFetch(200, {
      status: 'claimed',
      restaurant: {
        id: 'r1',
        slug: 's',
        name: 'X',
        claimed_at: '2026-04-30T00:00:00Z',
        claimed_by_user_id: 'u1',
      },
    });
    await verifyClaim('s', 'tok-abc', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toBe('/api/restaurants/s/claim/verify?t=tok-abc');
  });

  it('URL-encodes both slug and token (defense-in-depth)', async () => {
    const fetchImpl = fakeFetch(200, { status: 'claimed', restaurant: { id: 'r1', slug: 's', name: 'X', claimed_at: '', claimed_by_user_id: 'u' } });
    await verifyClaim('a/b', 'tok with space', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('/api/restaurants/a%2Fb/claim/verify');
    expect(url).toContain('t=tok%20with%20space');
  });

  it('surfaces the ExpiredTokenError kind from the API', async () => {
    const fetchImpl = fakeFetch(422, { error: 'token expired', kind: 'ExpiredTokenError' });
    try {
      await verifyClaim('s', 'old', { fetchImpl });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e).toBeInstanceOf(ClaimError);
      expect((e as ClaimError).kind).toBe('ExpiredTokenError');
    }
  });
});
