/**
 * Phase 6.6 — createRestaurant (mobile) + friendlyScanError mapping.
 */
import {
  createRestaurant,
  RestaurantCreateError,
} from '../../lib/api/restaurants';
import {
  friendlyScanError,
  IngestionUploadError,
} from '../../lib/api/ingestion-runs';

function fakeFetch(status: number, body: unknown) {
  return jest.fn(async () =>
    ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    }) as unknown as Response,
  );
}

describe('createRestaurant', () => {
  it('POSTs with the JWT and returns created on 201', async () => {
    const fetchImpl = fakeFetch(201, { id: 'r-1', slug: 'marias', name: "Maria's", status: 'draft' });

    const result = await createRestaurant({
      name: "Maria's",
      citySlug: 'durango',
      jwt: 'jwt-1',
      fetchImpl,
    });

    expect(result).toEqual({
      kind: 'created',
      restaurant: { id: 'r-1', slug: 'marias', name: "Maria's", status: 'draft' },
    });
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toContain('/api/v1/restaurants');
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer jwt-1');
    expect(JSON.parse(init.body as string)).toMatchObject({
      name: "Maria's",
      city_slug: 'durango',
    });
  });

  it('returns duplicates on 409 instead of throwing', async () => {
    const candidates = [
      { id: 'r-9', slug: 'marias', name: "Maria's Tacos", status: 'published', street: null },
    ];
    const fetchImpl = fakeFetch(409, { error: 'possible_duplicate', candidates });

    const result = await createRestaurant({
      name: 'Marias Taco',
      citySlug: 'durango',
      jwt: 'jwt-1',
      fetchImpl,
    });

    expect(result).toEqual({ kind: 'duplicates', candidates });
  });

  it('sends force "true" when overriding', async () => {
    const fetchImpl = fakeFetch(201, { id: 'r-2', slug: 'x', name: 'X', status: 'draft' });

    await createRestaurant({ name: 'X', citySlug: 'durango', force: true, jwt: 'jwt-1', fetchImpl });

    const [, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(JSON.parse(init.body as string).force).toBe('true');
  });

  it('throws RestaurantCreateError on other failures', async () => {
    const fetchImpl = fakeFetch(404, { error: 'unknown_city' });

    await expect(
      createRestaurant({ name: 'X', citySlug: 'atlantis', jwt: 'jwt-1', fetchImpl }),
    ).rejects.toBeInstanceOf(RestaurantCreateError);
  });
});

describe('friendlyScanError', () => {
  it('maps 429 with the limit from the body', () => {
    const err = new IngestionUploadError(429, { error: 'quota_exceeded', limit: 5 });
    expect(friendlyScanError(err)).toBe('Daily scan limit reached (5/day) — try again tomorrow.');
  });

  it('maps 503 budget exhaustion', () => {
    const err = new IngestionUploadError(503, { error: 'cost_ceiling_reached' });
    expect(friendlyScanError(err)).toMatch(/budget is used up/);
  });

  it('maps 403 foreign-draft', () => {
    const err = new RestaurantCreateError(403, { error: 'forbidden_restaurant' });
    expect(friendlyScanError(err)).toMatch(/someone else's draft/);
  });

  it('falls back to the raw message', () => {
    expect(friendlyScanError(new Error('boom'))).toBe('boom');
  });
});
