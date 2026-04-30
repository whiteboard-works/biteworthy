import { describe, expect, it, vi } from 'vitest';
import {
  fetchRestaurant,
  fetchRestaurantItems,
  groupItemsBySection,
  type FilteredItem,
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

describe('groupItemsBySection', () => {
  function item(overrides: Partial<FilteredItem>): FilteredItem {
    return {
      id: overrides.id ?? 'item-?',
      restaurant_id: 'rest-1',
      name: 'Item',
      description: '',
      confidence: 'confirmed',
      popularity: 0,
      ingredient_ids: [],
      tag_ids: [],
      menu_section_id: null,
      menu_section_name: null,
      status: 'visible',
      reasons: [],
      ...overrides,
    };
  }

  it('groups by menu_section_id, preserves server order', () => {
    const sections = groupItemsBySection([
      item({ id: 'a', menu_section_id: 'tacos', menu_section_name: 'Tacos' }),
      item({ id: 'b', menu_section_id: 'bowls', menu_section_name: 'Bowls' }),
      item({ id: 'c', menu_section_id: 'tacos', menu_section_name: 'Tacos' }),
    ]);
    expect(sections.map((s) => s.name)).toEqual(['Tacos', 'Bowls']);
    expect(sections[0]!.visible.map((i) => i.id)).toEqual(['a', 'c']);
  });

  it('drops null-section items into "Other"', () => {
    const sections = groupItemsBySection([item({ id: 'a' })]);
    expect(sections[0]!.name).toBe('Other');
  });

  it('separates visible vs hidden within a section', () => {
    const sections = groupItemsBySection([
      item({ id: 'v', status: 'visible', menu_section_id: 's', menu_section_name: 'S' }),
      item({
        id: 'h',
        status: 'hidden',
        menu_section_id: 's',
        menu_section_name: 'S',
        reasons: [
          {
            kind: 'avoid_ingredient',
            ingredient_id: 'ing-x',
            ingredient_name: 'Cheese',
            ingredient_family: 'dairy',
          },
        ],
      }),
    ]);
    expect(sections[0]!.visible.map((i) => i.id)).toEqual(['v']);
    expect(sections[0]!.hidden.map((i) => i.id)).toEqual(['h']);
  });
});
