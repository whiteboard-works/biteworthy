import { describe, expect, it, vi } from 'vitest';
import {
  createSuggestion,
  decideSuggestion,
  fetchSuggestionsForRestaurant,
  SuggestionError,
} from '../suggestions';

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

const sample = {
  id: 'sg-1',
  kind: 'add_ingredient',
  status: 'pending',
  payload: { ingredient_slug: 'herb-cilantro' },
  created_at: '2026-04-30T13:00:00Z',
  resolved_at: null,
  item: { id: 'item-1', name: 'Carne Taco', restaurant_id: 'rest-1' },
  submitter: { id: 'u-1', handle: 'diner', display_name: 'Diner' },
};

describe('createSuggestion', () => {
  it('POSTs JSON to the Next proxy with credentials', async () => {
    const fetchImpl = fakeFetch(201, sample);
    await createSuggestion('item-1', { kind: 'add_ingredient', payload: { ingredient_slug: 'herb-cilantro' } }, { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/items/item-1/suggestions');
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect(JSON.parse(init.body as string)).toEqual({
      kind: 'add_ingredient',
      payload: { ingredient_slug: 'herb-cilantro' },
    });
  });

  it('throws SuggestionError on 422', async () => {
    const fetchImpl = fakeFetch(422, { error: 'Unsupported kind', allowed: ['rename'] });
    await expect(
      createSuggestion('item-1', { kind: 'add_ingredient', payload: {} }, { fetchImpl }),
    ).rejects.toBeInstanceOf(SuggestionError);
  });
});

describe('fetchSuggestionsForRestaurant', () => {
  it('GETs the restaurant queue with credentials', async () => {
    const fetchImpl = fakeFetch(200, { suggestions: [sample] });
    const res = await fetchSuggestionsForRestaurant('cream-bean-berry-1', { fetchImpl });
    expect(res.suggestions).toHaveLength(1);
    expect(String(fetchImpl.mock.calls[0]![0])).toBe('/api/restaurants/cream-bean-berry-1/suggestions');
  });

  it('throws preserving status (so a 401 caller bounces to /login)', async () => {
    const fetchImpl = fakeFetch(401, { error: 'Not signed in' });
    await expect(fetchSuggestionsForRestaurant('s', { fetchImpl })).rejects.toMatchObject({
      name: 'SuggestionError',
      status: 401,
    });
  });

  it('preserves a 403 status (UI shows "you do not own this restaurant")', async () => {
    const fetchImpl = fakeFetch(403, { error: 'Only the claimed-restaurant owner can do that' });
    await expect(fetchSuggestionsForRestaurant('s', { fetchImpl })).rejects.toMatchObject({
      status: 403,
    });
  });
});

describe('decideSuggestion', () => {
  it('PATCHes the proxy with the decision body', async () => {
    const fetchImpl = fakeFetch(200, { ...sample, status: 'accepted' });
    await decideSuggestion('sg-1', 'accepted', { fetchImpl });
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(init.body as string)).toEqual({ decision: 'accepted' });
  });

  it('preserves InvalidPayloadError kind from the API', async () => {
    const fetchImpl = fakeFetch(422, { error: 'tag not found', kind: 'InvalidPayloadError' });
    try {
      await decideSuggestion('sg-1', 'accepted', { fetchImpl });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e).toBeInstanceOf(SuggestionError);
      expect((e as SuggestionError).kind).toBe('InvalidPayloadError');
    }
  });
});
