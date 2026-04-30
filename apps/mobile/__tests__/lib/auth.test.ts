// Mock expo-secure-store with an in-memory store before importing
// the SUT, so the wrapper exercises real persistence semantics.
jest.mock('expo-secure-store', () => {
  const store = new Map<string, string>();
  return {
    __memstore: store,
    getItemAsync: jest.fn(async (key: string) => store.get(key) ?? null),
    setItemAsync: jest.fn(async (key: string, value: string) => {
      store.set(key, value);
    }),
    deleteItemAsync: jest.fn(async (key: string) => {
      store.delete(key);
    }),
  };
});

import { AuthError, clearJwt, getJwt, login, logout, setJwt, signup } from '../../lib/auth';

const SecureStore = jest.requireMock('expo-secure-store') as {
  __memstore: Map<string, string>;
  getItemAsync: jest.Mock;
  setItemAsync: jest.Mock;
  deleteItemAsync: jest.Mock;
};

beforeEach(() => {
  SecureStore.__memstore.clear();
  SecureStore.getItemAsync.mockClear();
  SecureStore.setItemAsync.mockClear();
  SecureStore.deleteItemAsync.mockClear();
});

type FetchArgs = Parameters<typeof fetch>;

function fakeFetch(status: number, body: unknown, headers: Record<string, string> = {}) {
  return jest.fn(async (..._args: FetchArgs) =>
    ({
      ok: status >= 200 && status < 300,
      status,
      headers: {
        get: (name: string) => headers[name] ?? null,
      },
      json: async () => body,
    }) as unknown as Response,
  );
}

describe('getJwt / setJwt / clearJwt', () => {
  it('round-trips a token through SecureStore', async () => {
    await setJwt('header.payload.sig');
    expect(await getJwt()).toBe('header.payload.sig');
  });

  it('returns null when nothing is stored', async () => {
    expect(await getJwt()).toBeNull();
  });

  it('clears the stored token', async () => {
    await setJwt('jjj');
    await clearJwt();
    expect(await getJwt()).toBeNull();
  });

  it('returns null when SecureStore throws (e.g. simulator without keychain)', async () => {
    SecureStore.getItemAsync.mockRejectedValueOnce(new Error('no keychain'));
    expect(await getJwt()).toBeNull();
  });
});

describe('login', () => {
  const userPayload = { user: { id: 'u1', email: 'a@b.com', handle: null, display_name: null } };

  it('POSTs credentials, persists the token from the Authorization header, returns the user', async () => {
    const fetchImpl = fakeFetch(200, userPayload, { Authorization: 'Bearer header.body.sig' });
    const user = await login('a@b.com', 'sekret123', { fetchImpl });

    expect(user.email).toBe('a@b.com');
    expect(await getJwt()).toBe('header.body.sig');

    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(JSON.parse(init.body as string)).toEqual({
      user: { email: 'a@b.com', password: 'sekret123' },
    });
  });

  it('throws AuthError on bad credentials and does not persist anything', async () => {
    const fetchImpl = fakeFetch(401, { error: 'invalid' });
    await expect(login('a@b.com', 'wrong', { fetchImpl })).rejects.toMatchObject({
      name: 'AuthError',
      status: 401,
    });
    expect(await getJwt()).toBeNull();
  });

  it('throws when the upstream forgets to send the Authorization header', async () => {
    const fetchImpl = fakeFetch(200, userPayload, {}); // no Authorization
    await expect(login('a@b.com', 'sekret123', { fetchImpl })).rejects.toBeInstanceOf(AuthError);
    expect(await getJwt()).toBeNull();
  });
});

describe('signup', () => {
  it('POSTs to /api/v1/auth/signup', async () => {
    const fetchImpl = fakeFetch(
      200,
      { user: { id: 'u2', email: 'b@c.com', handle: null, display_name: null } },
      { Authorization: 'Bearer fresh.token.here' },
    );
    await signup('b@c.com', 'longerpw1', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('/api/v1/auth/signup');
    expect(await getJwt()).toBe('fresh.token.here');
  });
});

describe('logout', () => {
  it('clears the stored token even when the upstream call fails', async () => {
    await setJwt('persisted.jwt');
    const fetchImpl = jest.fn(async () => {
      throw new Error('network down');
    });
    await logout({ fetchImpl: fetchImpl as unknown as typeof fetch });
    expect(await getJwt()).toBeNull();
  });

  it('best-effort calls the API logout when a token is present', async () => {
    await setJwt('persisted.jwt');
    const fetchImpl = fakeFetch(204, {});
    await logout({ fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toContain('/api/v1/auth/logout');
    expect(init.method).toBe('DELETE');
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer persisted.jwt');
  });

  it('skips the API call when no token is stored', async () => {
    const fetchImpl = jest.fn();
    await logout({ fetchImpl: fetchImpl as unknown as typeof fetch });
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
