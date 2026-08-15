import { describe, expect, it, vi } from 'vitest';
import { ApiError } from '../../../../lib/api';
import { resolveMenuItems } from '../_resolve-items';
import type { RestaurantItemsResponse } from '../../../../lib/restaurants';

const MENU = { restaurant_id: 'r1', filter: {}, items: [] } as unknown as RestaurantItemsResponse;

/**
 * The intent this file pins: a dead share token or unknown preset must
 * never 404 a live restaurant page (the confirmed-live bug), while a
 * transient API error must never be blamed on the user's link.
 */
describe('resolveMenuItems', () => {
  it('passes a clean fetch straight through', async () => {
    const fetch = vi.fn().mockResolvedValue(MENU);
    const r = await resolveMenuItems(fetch, 'tok', 'celiac');
    expect(r).toEqual({ items: MENU, shareTokenInvalid: false, presetInvalid: false });
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it('drops a 422-refused token and retries, keeping the preset', async () => {
    const fetch = vi
      .fn()
      .mockRejectedValueOnce(new ApiError(422, '422 Unprocessable Entity'))
      .mockResolvedValueOnce(MENU);
    const r = await resolveMenuItems(fetch, 'dead-tok', 'celiac');
    expect(r.shareTokenInvalid).toBe(true);
    expect(r.presetInvalid).toBe(false);
    expect(r.items).toBe(MENU);
    expect(fetch).toHaveBeenLastCalledWith(undefined, 'celiac');
  });

  it('drops a 404-unknown preset and retries, keeping the token', async () => {
    const fetch = vi
      .fn()
      .mockRejectedValueOnce(new ApiError(404, '404 Not Found'))
      .mockResolvedValueOnce(MENU);
    const r = await resolveMenuItems(fetch, 'tok', 'no-such-diet');
    expect(r.presetInvalid).toBe(true);
    expect(r.shareTokenInvalid).toBe(false);
    expect(fetch).toHaveBeenLastCalledWith('tok', undefined);
  });

  it('sheds both params when both are bad', async () => {
    const fetch = vi
      .fn()
      .mockRejectedValueOnce(new ApiError(422, '422'))
      .mockRejectedValueOnce(new ApiError(404, '404'))
      .mockResolvedValueOnce(MENU);
    const r = await resolveMenuItems(fetch, 'dead-tok', 'no-such-diet');
    expect(r).toEqual({ items: MENU, shareTokenInvalid: true, presetInvalid: true });
    expect(fetch).toHaveBeenLastCalledWith(undefined, undefined);
  });

  it('does NOT blame the link for a transient 500 — null, no flags, no retry', async () => {
    const fetch = vi.fn().mockRejectedValue(new ApiError(500, '500 Internal Server Error'));
    const r = await resolveMenuItems(fetch, 'tok', 'celiac');
    expect(r).toEqual({ items: null, shareTokenInvalid: false, presetInvalid: false });
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it('treats a non-ApiError (network) the same way', async () => {
    const fetch = vi.fn().mockRejectedValue(new Error('fetch failed'));
    const r = await resolveMenuItems(fetch, 'tok', undefined);
    expect(r).toEqual({ items: null, shareTokenInvalid: false, presetInvalid: false });
  });

  it('a restaurant-level 404 with no params stays a plain not-found', async () => {
    const fetch = vi.fn().mockRejectedValue(new ApiError(404, '404 Not Found'));
    const r = await resolveMenuItems(fetch, undefined, undefined);
    expect(r).toEqual({ items: null, shareTokenInvalid: false, presetInvalid: false });
    expect(fetch).toHaveBeenCalledTimes(1);
  });
});
