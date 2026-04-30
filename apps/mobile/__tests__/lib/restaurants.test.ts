import {
  fetchRestaurant,
  fetchRestaurantItems,
  groupItemsBySection,
  RestaurantFetchError,
  type FilteredItem,
  type Restaurant,
  type RestaurantItemsResponse,
} from '../../lib/api/restaurants';

type FetchCall = Parameters<typeof fetch>;
type FetchMock = jest.Mock<Promise<Response>, FetchCall>;

function fakeFetch(status: number, body: unknown): FetchMock {
  return jest.fn(async (..._args: FetchCall) =>
    ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    }) as unknown as Response,
  ) as FetchMock;
}

const restaurantPayload: Restaurant = {
  id: 'rest-1',
  slug: 'ninis-1',
  name: 'Ninis Taqueria',
  about: null,
  phone: null,
  website: null,
  status: 'published',
  city: { id: 'city-1', slug: 'durango', name: 'Durango', region: 'CO' },
};

const itemsPayload: RestaurantItemsResponse = {
  restaurant_id: 'rest-1',
  filter: {
    source: 'preset',
    preset_slug: 'vegan',
    strictness: 'balanced',
    avoid_ingredient_ids: ['ing-cheese'],
    avoid_tag_ids: [],
  },
  items: [],
};

describe('fetchRestaurant', () => {
  it('GETs /api/v1/restaurants/:id and returns the JSON', async () => {
    const fetchImpl = fakeFetch(200, restaurantPayload);
    const r = await fetchRestaurant('rest-1', { fetchImpl });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(String(fetchImpl.mock.calls[0]![0])).toContain('/api/v1/restaurants/rest-1');
    expect(r.name).toBe('Ninis Taqueria');
  });

  it('throws RestaurantFetchError on non-2xx', async () => {
    const fetchImpl = fakeFetch(404, { error: 'not found' });
    await expect(fetchRestaurant('missing', { fetchImpl })).rejects.toBeInstanceOf(
      RestaurantFetchError,
    );
  });
});

describe('fetchRestaurantItems', () => {
  it('omits the Authorization header when no JWT supplied (anonymous browse)', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItems('rest-1', { fetchImpl });
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
  });

  it('attaches Bearer JWT when provided', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItems('rest-1', { fetchImpl, jwt: 'jjj.www.ttt' });
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer jjj.www.ttt');
  });

  it('passes presetSlug + strictness as query params', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItems('rest-1', {
      fetchImpl,
      presetSlug: 'vegan',
      strictness: 'strict',
    });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('profile=vegan');
    expect(url).toContain('strictness=strict');
  });

  it('omits the strictness param when undefined (server keeps profile default)', async () => {
    const fetchImpl = fakeFetch(200, itemsPayload);
    await fetchRestaurantItems('rest-1', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).not.toContain('strictness=');
  });

  it('passes each strictness value verbatim (relaxed | balanced | strict)', async () => {
    for (const s of ['relaxed', 'balanced', 'strict'] as const) {
      const fetchImpl = fakeFetch(200, itemsPayload);
      await fetchRestaurantItems('rest-1', { fetchImpl, strictness: s });
      const url = String(fetchImpl.mock.calls[0]![0]);
      expect(url).toContain(`strictness=${s}`);
    }
  });
});

describe('groupItemsBySection', () => {
  function item(overrides: Partial<FilteredItem>): FilteredItem {
    return {
      id: overrides.id ?? 'item-?',
      restaurant_id: 'rest-1',
      name: overrides.name ?? 'Item',
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

  it('groups items by menu_section_id, preserving server order', () => {
    const sections = groupItemsBySection([
      item({ id: 'a', menu_section_id: 'tacos', menu_section_name: 'Tacos' }),
      item({ id: 'b', menu_section_id: 'bowls', menu_section_name: 'Bowls' }),
      item({ id: 'c', menu_section_id: 'tacos', menu_section_name: 'Tacos' }),
    ]);
    expect(sections.map((s) => s.name)).toEqual(['Tacos', 'Bowls']);
    expect(sections[0]!.visible.map((i) => i.id)).toEqual(['a', 'c']);
    expect(sections[1]!.visible.map((i) => i.id)).toEqual(['b']);
  });

  it('separates visible vs hidden items within a section', () => {
    const sections = groupItemsBySection([
      item({ id: 'v1', menu_section_id: 's1', menu_section_name: 'S1', status: 'visible' }),
      item({
        id: 'h1',
        menu_section_id: 's1',
        menu_section_name: 'S1',
        status: 'hidden',
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
    expect(sections[0]!.visible.map((i) => i.id)).toEqual(['v1']);
    expect(sections[0]!.hidden.map((i) => i.id)).toEqual(['h1']);
  });

  it('drops items with no menu_section into a single "Other" group', () => {
    const sections = groupItemsBySection([
      item({ id: 'a', menu_section_id: null, menu_section_name: null }),
      item({ id: 'b', menu_section_id: null, menu_section_name: null }),
    ]);
    expect(sections).toHaveLength(1);
    expect(sections[0]!.name).toBe('Other');
    expect(sections[0]!.visible.map((i) => i.id)).toEqual(['a', 'b']);
  });

  it('returns an empty array for no items', () => {
    expect(groupItemsBySection([])).toEqual([]);
  });
});
