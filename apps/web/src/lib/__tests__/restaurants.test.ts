import { describe, expect, it, vi } from 'vitest';
import {
  clearNeverHide,
  fetchRestaurant,
  fetchRestaurantItems,
  fetchRestaurantItemsClient,
  fetchRestaurants,
  setItemFavorite,
  setNeverHide,
  setRestaurantFavorite,
  type Restaurant,
  type RestaurantItemsResponse,
  type RestaurantSummary,
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

describe('fetchRestaurantItemsClient', () => {
  // The menu is filtered by who is asking. A browser fetch straight to
  // Rails is cross-origin and carries no `bw_session`, so it would answer
  // a signed-in reader with the anonymous menu — which is exactly what the
  // strictness toggle used to do.
  it('goes through the Next proxy with same-origin credentials when signed in', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItemsClient('cream-bean-berry-1', { fetchImpl, signedIn: true });

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/restaurants/cream-bean-berry-1/items');
    expect(init.credentials).toBe('same-origin');
    expect((init.headers as Record<string, string> | undefined)?.Authorization).toBeUndefined();
  });

  // Anonymous readers stay off the proxy: it reaches Rails from the Next
  // server's IP, and rack-attack's ceiling keys on that IP — so proxying
  // the highest-volume read for callers with no credential to carry would
  // let ordinary browsing exhaust a bucket meant to catch scrapers.
  it('goes straight to Rails when anonymous', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItemsClient('cream-bean-berry-1', { fetchImpl });

    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('/api/v1/restaurants/cream-bean-berry-1/items');
    expect(url).not.toMatch(/^\/api\/restaurants/);
  });

  it('forwards strictness and the share token on both routes', async () => {
    for (const signedIn of [true, false]) {
      const fetchImpl = fakeFetch(200, itemsPayload);
      await fetchRestaurantItemsClient('cream-bean-berry-1', {
        fetchImpl,
        signedIn,
        strictness: 'strict',
        profileToken: 'tok-123',
      });
      const url = String(fetchImpl.mock.calls[0]![0]);
      expect(url).toContain('strictness=strict');
      expect(url).toContain('profile_token=tok-123');
    }
  });

  // The proxy relays with `new NextResponse(body, { status })`, which has
  // no statusText — echoing it rendered "Could not refresh items — 404 ".
  it('surfaces the upstream error message rather than an empty statusText', async () => {
    const fetchImpl = fakeFetch(404, { error: 'Restaurant not found' });
    await expect(
      fetchRestaurantItemsClient('cream-bean-berry-1', { fetchImpl, signedIn: true }),
    ).rejects.toThrow('Restaurant not found');
  });

  it('falls back to the status when upstream sends no JSON error', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: false,
      status: 502,
      json: async () => {
        throw new Error('not json');
      },
    })) as unknown as typeof fetch;
    await expect(
      fetchRestaurantItemsClient('cream-bean-berry-1', { fetchImpl, signedIn: true }),
    ).rejects.toThrow(/502/);
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

describe('setItemFavorite / setRestaurantFavorite', () => {
  it('POSTs to favorite a dish and DELETEs to unfavorite', async () => {
    const post = fakeFetch(200, { item_id: 'item-1', favorited: true });
    expect((await setItemFavorite('item-1', true, { fetchImpl: post })).favorited).toBe(true);
    expect(String(post.mock.calls[0]![0])).toBe('/api/items/item-1/favorite');
    expect((post.mock.calls[0]![1] as RequestInit).method).toBe('POST');

    const del = fakeFetch(200, { item_id: 'item-1', favorited: false });
    expect((await setItemFavorite('item-1', false, { fetchImpl: del })).favorited).toBe(false);
    expect((del.mock.calls[0]![1] as RequestInit).method).toBe('DELETE');
  });

  it('favorites a restaurant by slug', async () => {
    const fetchImpl = fakeFetch(200, { restaurant_id: 'r1', favorited: true });
    const result = await setRestaurantFavorite('ninis', true, { fetchImpl });
    expect(result.favorited).toBe(true);
    expect(String(fetchImpl.mock.calls[0]![0])).toBe('/api/restaurants/ninis/favorite');
    expect((fetchImpl.mock.calls[0]![1] as RequestInit).method).toBe('POST');
  });

  it('throws on non-2xx', async () => {
    const fetchImpl = fakeFetch(401, { error: 'unauth' });
    await expect(setItemFavorite('item-1', true, { fetchImpl })).rejects.toThrow(/401/);
  });
});

describe('fetchRestaurants', () => {
  const summary: RestaurantSummary = {
    id: 'r1',
    slug: 'marias',
    name: "Maria's Tacos",
    status: 'published',
    city: { slug: 'durango', name: 'Durango', region: 'CO' },
    street: null,
    latitude: null,
    longitude: null,
  };

  it('GETs the published list and unwraps { restaurants }', async () => {
    const fetchImpl = fakeFetch(200, { restaurants: [summary] });

    const result = await fetchRestaurants({ fetchImpl });

    expect(result).toEqual([summary]);
    const [url] = fetchImpl.mock.calls[0] as unknown as [string];
    expect(url).toContain('/api/v1/restaurants');
  });

  it('appends ?q= when a search term is given', async () => {
    const fetchImpl = fakeFetch(200, { restaurants: [] });

    await fetchRestaurants({ q: 'taco', fetchImpl });

    const [url] = fetchImpl.mock.calls[0] as unknown as [string];
    expect(url).toContain('/restaurants?q=taco');
  });
});
