import { describe, expect, it, vi } from 'vitest';
import { isValidEmail, submitWaitlist, WaitlistError } from '../waitlist';

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

describe('isValidEmail', () => {
  it('accepts a normal email', () => {
    expect(isValidEmail('skylar@example.com')).toBe(true);
  });

  it('rejects obvious malformed inputs (no @, no ., whitespace)', () => {
    for (const bad of ['', 'skylar', 'skylar@', '@example.com', 'sky lar@a.com', 'skylar@example']) {
      expect(isValidEmail(bad)).toBe(false);
    }
  });

  it('strips whitespace before checking', () => {
    expect(isValidEmail('  skylar@example.com  ')).toBe(true);
  });
});

describe('submitWaitlist', () => {
  it('POSTs JSON to the Next proxy at /api/waitlist with email + source', async () => {
    const fetchImpl = fakeFetch(200, { ok: true, duplicate: false });
    const res = await submitWaitlist('skylar@example.com', 'landing', { fetchImpl });
    expect(res.duplicate).toBe(false);

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/waitlist');
    expect(init.method).toBe('POST');
    expect((init.headers as Record<string, string>)['Content-Type']).toBe('application/json');
    expect(JSON.parse(init.body as string)).toEqual({
      email: 'skylar@example.com',
      source: 'landing',
    });
  });

  it('defaults source to "landing" when not specified', async () => {
    const fetchImpl = fakeFetch(200, { ok: true, duplicate: false });
    await submitWaitlist('s@e.com', undefined, { fetchImpl });
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(JSON.parse(init.body as string).source).toBe('landing');
  });

  it('returns the duplicate=true flag when the API reports it', async () => {
    const fetchImpl = fakeFetch(200, { ok: true, duplicate: true });
    const res = await submitWaitlist('s@e.com', 'press', { fetchImpl });
    expect(res.duplicate).toBe(true);
  });

  it('throws WaitlistError preserving the upstream status on 422', async () => {
    const fetchImpl = fakeFetch(422, { ok: false, errors: ['Email is invalid'] });
    await expect(submitWaitlist('garbage', 'landing', { fetchImpl })).rejects.toMatchObject({
      name: 'WaitlistError',
      status: 422,
    });
  });
});
