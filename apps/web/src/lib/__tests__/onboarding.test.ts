import { describe, expect, it, vi } from 'vitest';
import {
  fetchDietaryProfiles,
  saveProfile,
  searchIngredients,
  type SaveProfilePayload,
} from '../onboarding';

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

describe('fetchDietaryProfiles', () => {
  it('GETs /api/v1/dietary_profiles and unwraps the array', async () => {
    const fetchImpl = fakeFetch(200, {
      dietary_profiles: [
        {
          id: 'p1',
          slug: 'vegan',
          name: 'Vegan',
          description: 'No animal products.',
          avoid_ingredient_ids: ['ing-dairy'],
          avoid_tag_ids: ['tag-cd'],
        },
      ],
    });
    const presets = await fetchDietaryProfiles({ fetchImpl });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(String(fetchImpl.mock.calls[0]![0])).toContain('/api/v1/dietary_profiles');
    expect(presets).toHaveLength(1);
    expect(presets[0]!.slug).toBe('vegan');
  });
});

describe('searchIngredients', () => {
  it('passes ?q= when the query is non-empty', async () => {
    const fetchImpl = fakeFetch(200, { ingredients: [] });
    await searchIngredients('cilantro', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('q=cilantro');
    expect(url).toContain('limit=20');
  });

  it('omits ?q= for empty / whitespace queries', async () => {
    const fetchImpl = fakeFetch(200, { ingredients: [] });
    await searchIngredients('   ', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).not.toContain('q=');
    expect(url).toContain('limit=20');
  });

  it('returns the unwrapped array', async () => {
    const fetchImpl = fakeFetch(200, {
      ingredients: [
        { id: 'i1', slug: 'cilantro', name: 'Cilantro', path: 'herb.cilantro', aliases: [], allergen: false },
      ],
    });
    const out = await searchIngredients('cilantro', { fetchImpl });
    expect(out[0]!.name).toBe('Cilantro');
  });
});

describe('saveProfile', () => {
  const payload: SaveProfilePayload = {
    avoid_ingredient_ids: ['ing-dairy'],
    avoid_tag_ids: ['tag-cd'],
    prefer_tag_ids: [],
    strictness: 'balanced',
  };

  it('PATCHes the Next proxy at /api/profile with credentials (no client-side JWT)', async () => {
    const fetchImpl = fakeFetch(200, {});
    await saveProfile(payload, { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/profile');
    expect(init.method).toBe('PATCH');
    expect(init.credentials).toBe('same-origin');
    // The Next proxy injects the Authorization header from the cookie.
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
    expect(JSON.parse(init.body as string)).toEqual(payload);
  });

  it('throws on non-2xx so the screen can route a 401 to /login', async () => {
    const fetchImpl = fakeFetch(401, { error: 'Not signed in' });
    await expect(saveProfile(payload, { fetchImpl })).rejects.toThrow(/401/);
  });
});
