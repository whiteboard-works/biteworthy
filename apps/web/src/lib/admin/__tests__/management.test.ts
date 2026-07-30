import { describe, expect, it, vi } from 'vitest';

/**
 * The management fetchers' wire contract: the UI's "community" toggle
 * must serialize as filter=community_published and "admins only" as
 * is_admin=true — the exact strings Rails matches; anything else
 * silently unfilters. Restaurant updates must be able to carry null
 * to clear optional fields (a '' would overwrite NULLs server-side).
 */
import {
  fetchAdminRestaurants,
  fetchAdminUsers,
  setUserAdmin,
  updateAdminRestaurant,
} from '../management';

function ok(body: unknown) {
  return vi.fn().mockResolvedValue({ ok: true, json: async () => body });
}

describe('admin management lib', () => {
  it('maps community/adminOnly to the exact server params', async () => {
    const impl = ok({ restaurants: [], pagination: { total: 0, limit: 25, offset: 0 } });
    await fetchAdminRestaurants({ community: true, status: 'published' }, impl as unknown as typeof fetch);
    expect(impl.mock.calls[0]![0]).toBe(
      '/api/admin/restaurants?status=published&filter=community_published',
    );

    const impl2 = ok({ users: [], pagination: { total: 0, limit: 25, offset: 0 } });
    await fetchAdminUsers({ adminOnly: true }, impl2 as unknown as typeof fetch);
    expect(impl2.mock.calls[0]![0]).toBe('/api/admin/users?is_admin=true');
  });

  it('restaurant updates serialize null clears verbatim', async () => {
    const impl = ok({ id: 'r1' });
    await updateAdminRestaurant('r1', { about: null, status: 'published' }, impl as unknown as typeof fetch);
    const body = JSON.parse((impl.mock.calls[0]![1] as { body: string }).body);
    expect(body).toEqual({ about: null, status: 'published' });
  });

  it('the is_admin toggle PATCHes the boolean', async () => {
    const impl = ok({ id: 'u1', is_admin: true });
    await setUserAdmin('u1', true, impl as unknown as typeof fetch);
    const [url, init] = impl.mock.calls[0]! as [string, { method: string; body: string }];
    expect(url).toBe('/api/admin/users/u1');
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(init.body)).toEqual({ is_admin: true });
  });
});
