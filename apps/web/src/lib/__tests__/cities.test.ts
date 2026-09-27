import { describe, expect, it, vi } from 'vitest';
import { fetchCities } from '../cities';

/**
 * fetchCities runs on the Next server without a cache; without the
 * forwarded visitor headers every visitor would share one Rails rate-limit
 * bucket and the add-a-restaurant form would go empty under load.
 */
describe('fetchCities', () => {
  it('forwards the edge headers to Rails', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(new Response(JSON.stringify({ cities: [] }), { status: 200 }));

    await fetchCities({ fetchImpl, edgeHeaders: { 'X-BW-Client-IP': '203.0.113.9' } });

    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect((init.headers as Record<string, string>)['X-BW-Client-IP']).toBe('203.0.113.9');
  });
});
