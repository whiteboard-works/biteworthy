import { describe, expect, it, vi } from 'vitest';
import { AuthError, login, logout, signup } from '../auth';

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

describe('login', () => {
  it('POSTs to /api/auth/login with credentials + JSON body', async () => {
    const fetchImpl = fakeFetch(200, { user: { id: 'u1', email: 'a@b.com', handle: null, display_name: null } });
    const result = await login('a@b.com', 'sekret123', { fetchImpl });
    expect(result.user.email).toBe('a@b.com');

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/auth/login');
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect(JSON.parse(init.body as string)).toEqual({ email: 'a@b.com', password: 'sekret123' });
  });

  it('throws AuthError carrying status on bad credentials', async () => {
    const fetchImpl = fakeFetch(401, { error: 'Auth failed: 401' });
    await expect(login('a@b.com', 'wrong', { fetchImpl })).rejects.toMatchObject({
      name: 'AuthError',
      status: 401,
    });
  });
});

describe('signup', () => {
  it('POSTs to /api/auth/signup', async () => {
    const fetchImpl = fakeFetch(200, { user: { id: 'u2', email: 'b@c.com', handle: null, display_name: null } });
    await signup('b@c.com', 'longerpw1', { fetchImpl });
    expect(String(fetchImpl.mock.calls[0]![0])).toBe('/api/auth/signup');
  });

  it('throws AuthError on duplicate email', async () => {
    const fetchImpl = fakeFetch(422, { error: 'taken' });
    await expect(signup('b@c.com', 'longerpw1', { fetchImpl })).rejects.toBeInstanceOf(AuthError);
  });
});

describe('logout', () => {
  it('POSTs to /api/auth/logout with credentials and no body', async () => {
    const fetchImpl = fakeFetch(200, { ok: true });
    await logout({ fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/auth/logout');
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect(init.body).toBeUndefined();
  });

  it('throws AuthError on non-2xx', async () => {
    const fetchImpl = fakeFetch(500, { error: 'logout failed' });
    await expect(logout({ fetchImpl })).rejects.toBeInstanceOf(AuthError);
  });
});
