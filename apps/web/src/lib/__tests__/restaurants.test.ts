import { describe, expect, it, vi } from 'vitest';
import {
  clearNeverHide,
  fetchRestaurant,
  fetchRestaurantItems,
  setNeverHide,
  type Restaurant,
  type RestaurantItemsResponse,
} from '../restaurants';

const restaurantPayload: Restaurant = {
  id: 'rest-1',
  slug: 'cream-bean-berry-1',
  name: 'Cream, Bean & Berry',
  about: null,
  phone: null,
  website: null,
  status: 'published',
  claimed_at: null,
  claimed_by_user_id: null,
  city: { id: 'city-1', slug: 'durango', name: 'Durango', region: 'CO' },
};

const itemsPayload: RestaurantItemsResponse = {
  restaurant_id: 'rest-1',
  filter: {
    source: 'none',
    preset_slug: null,
    strictness: 'balanced',
    avoid_ingredient_ids: [],
    avoid_tag_ids: [],
  },
  items: [],
};

type FetchArgs = Parameters<typeof fetch>;

function fakeFetch(status: number, body: unknown) {
  return vi.fn(
    async (..._args: FetchArgs) =>
      ({
        ok: status >= 200 && status < 300,
        status,
        statusText: status === 200 ? 'OK' : 'NOT FOUND',
        json: async () => body,
      }) as unknown as Response,
  );
}

describe('fetchRestaurant', () => {
  it('GETs /api/v1/restaurants/:slugOrId', async () => {
    const fetchImpl = fakeFetch(200, restaurantPayload);
    const r = await fetchRestaurant('cream-bean-berry-1', { fetchImpl });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(String(fetchImpl.mock.calls[0]![0])).toContain(
      '/api/v1/restaurants/cream-bean-berry-1',
    );
    expect(r.name).toBe('Cream, Bean & Berry');
  });

  it('encodes slugs that contain reserved URL characters', async () => {
    const fetchImpl = fakeFetch(200, restaurantPayload);
    await fetchRestaurant('café & co', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('caf%C3%A9%20%26%20co');
  });

  it('throws on non-2xx', async () => {
    const fetchImpl = fakeFetch(404, { error: 'not found' });
    await expect(fetchRestaurant('missing', { fetchImpl })).rejects.toThrow(/404/);
  });
});

describe('fetchRestaurantItems', () => {
  it('omits the strictness param when undefined', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItems('cream-bean-berry-1', { fetchImpl });
    expect(String(fetchImpl.mock.calls[0]![0])).not.toContain('strictness=');
  });

  it('passes photo_url through unchanged for items with + without an attached crop (phase 4.11.4)', async () => {
    const withPhoto = {
      id: 'item-1',
      restaurant_id: 'rest-1',
      name: 'Pad Thai',
      description: 'Rice noodles, peanut, lime.',
      confidence: 'confirmed',
      popularity: 0,
      ingredient_ids: [],
      tag_ids: [],
      menu_section_id: null,
      menu_section_name: null,
      status: 'visible',
      reasons: [],
      photo_url: 'https://api.bite-worthy.com/rails/active_storage/blobs/abc/dish-1.jpg',
    };
    const noPhoto = { ...withPhoto, id: 'item-2', name: 'Som Tum', photo_url: null };
    const fetchImpl = fakeFetch(200, { ...itemsPayload, items: [withPhoto, noPhoto] });

    const res = await fetchRestaurantItems('cream-bean-berry-1', { fetchImpl });

    expect(res.items[0]!.photo_url).toBe(withPhoto.photo_url);
    expect(res.items[1]!.photo_url).toBeNull();
  });

  it('passes presetSlug + strictness as query params', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItems('cream-bean-berry-1', {
      fetchImpl,
      presetSlug: 'celiac',
      strictness: 'strict',
    });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('profile=celiac');
    expect(url).toContain('strictness=strict');
  });

  it('attaches Bearer JWT when supplied', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItems('cream-bean-berry-1', { fetchImpl, jwt: 'jjj.www.ttt' });
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer jjj.www.ttt');
  });
});

describe('setNeverHide / clearNeverHide (Phase 4.2)', () => {
  it('POSTs the Next proxy with credentials and no client-side JWT header', async () => {
    const fetchImpl = fakeFetch(200, { item_id: 'item-1', overridden_by_user: true });
    const result = await setNeverHide('item-1', { fetchImpl });
    expect(result.overridden_by_user).toBe(true);

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/items/item-1/never_hide');
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect((init.headers as Record<string, string> | undefined)?.Authorization).toBeUndefined();
  });

  it('DELETE clears the override', async () => {
    const fetchImpl = fakeFetch(200, { item_id: 'item-1', overridden_by_user: false });
    const result = await clearNeverHide('item-1', { fetchImpl });
    expect(result.overridden_by_user).toBe(false);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(init.method).toBe('DELETE');
  });

  it('throws on non-2xx', async () => {
    const fetchImpl = fakeFetch(401, { error: 'unauth' });
    await expect(setNeverHide('item-1', { fetchImpl })).rejects.toThrow(/401/);
  });
});
