// In-memory expo-secure-store, same pattern as the auth test, so the
// prefs wrapper exercises real persistence semantics.
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

import { getAnalyticsOptIn, setAnalyticsOptIn, OPT_IN_KEY } from '../../lib/analytics-prefs';

const SecureStore = jest.requireMock('expo-secure-store') as {
  __memstore: Map<string, string>;
  getItemAsync: jest.Mock;
};

beforeEach(() => {
  SecureStore.__memstore.clear();
});

/**
 * Legal remediation E7b — mobile analytics are off by default; the
 * stored opt-in is the source of truth the root layout reads at boot.
 */
describe('analytics-prefs', () => {
  it('defaults to opted-out when nothing is stored', async () => {
    expect(await getAnalyticsOptIn()).toBe(false);
  });

  it('persists an opt-in and reads it back', async () => {
    await setAnalyticsOptIn(true);
    expect(SecureStore.__memstore.get(OPT_IN_KEY)).toBe('1');
    expect(await getAnalyticsOptIn()).toBe(true);
  });

  it('clears the opt-in when turned back off', async () => {
    await setAnalyticsOptIn(true);
    await setAnalyticsOptIn(false);
    expect(SecureStore.__memstore.has(OPT_IN_KEY)).toBe(false);
    expect(await getAnalyticsOptIn()).toBe(false);
  });

  it('returns false (default-off) when SecureStore throws', async () => {
    SecureStore.getItemAsync.mockRejectedValueOnce(new Error('no keychain'));
    expect(await getAnalyticsOptIn()).toBe(false);
  });
});
