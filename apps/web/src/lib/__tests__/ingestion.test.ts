import { describe, it, expect, vi } from 'vitest';
import {
  ingestFromFile,
  ingestFromUrl,
  IngestionRequestError,
  type IngestionRunPayload,
} from '../ingestion';

const sampleRun: IngestionRunPayload = {
  id: 'rrrr-1111',
  status: 'extracting',
  input_kind: 'url',
  restaurant_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  state_history: { extracting: '2026-04-30T01:00:00Z' },
  failure_message: null,
  api_cost_cents: 0,
  latency_ms: null,
  input_count: 1,
  ingestion_items_count: 0,
  created_at: '2026-04-30T01:00:00Z',
  updated_at: '2026-04-30T01:00:00Z',
};

function fakeFetch(status: number, body: unknown) {
  return vi.fn(async () =>
    ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    }) as unknown as Response,
  );
}

describe('ingestFromUrl', () => {
  it('POSTs to the Next proxy at /api/ingestion_runs with credentials', async () => {
    const fetchImpl = fakeFetch(201, sampleRun);

    const result = await ingestFromUrl({
      restaurantId: 'rest-1',
      sourceUrl: 'https://restaurant.example/menu',
      fetchImpl,
    });

    expect(result.id).toBe(sampleRun.id);
    const calls = fetchImpl.mock.calls as unknown as Array<[string, RequestInit]>;
    const [url, init] = calls[0]!;
    expect(url).toBe('/api/ingestion_runs');
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    // No Authorization header from the client — the Next proxy adds
    // it from the bw_session cookie.
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
    expect(init.headers).toMatchObject({ 'Content-Type': 'application/json' });
    expect(JSON.parse(init.body as string)).toEqual({
      restaurant_id: 'rest-1',
      source_url: 'https://restaurant.example/menu',
    });
  });

  it('throws IngestionRequestError carrying status + parsed body on failure', async () => {
    const fetchImpl = fakeFetch(422, { error: 'url_fetch_failed', reason: 'non_2xx', status: 503 });

    await expect(
      ingestFromUrl({
        restaurantId: 'rest-1',
        sourceUrl: 'https://broken.example/menu',
        fetchImpl,
      }),
    ).rejects.toMatchObject({
      status: 422,
      body: { error: 'url_fetch_failed', reason: 'non_2xx', status: 503 },
    });
  });
});

describe('ingestFromFile', () => {
  it('POSTs multipart with the file under inputs[] and no client-side auth header', async () => {
    const fetchImpl = fakeFetch(201, { ...sampleRun, input_kind: 'pdf' });
    const file = new File(['%PDF-1.4'], 'menu.pdf', { type: 'application/pdf' });

    const result = await ingestFromFile({
      restaurantId: 'rest-1',
      file,
      fetchImpl,
    });

    expect(result.input_kind).toBe('pdf');
    const calls = fetchImpl.mock.calls as unknown as Array<[string, RequestInit]>;
    const [, init] = calls[0]!;
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
    // No Content-Type either — let fetch set the multipart boundary itself.
    expect((init.headers as Record<string, string>)['Content-Type']).toBeUndefined();
    expect(init.body).toBeInstanceOf(FormData);
  });

  it('returns a typed IngestionRequestError on non-JSON 5xx', async () => {
    const fetchImpl = vi.fn(async () =>
      ({
        ok: false,
        status: 500,
        json: async () => {
          throw new Error('not json');
        },
      }) as unknown as Response,
    );
    const file = new File(['x'], 'x.pdf', { type: 'application/pdf' });

    await expect(
      ingestFromFile({
        restaurantId: 'rest-1',
        file,
        fetchImpl: fetchImpl as unknown as typeof fetch,
      }),
    ).rejects.toBeInstanceOf(IngestionRequestError);
  });
});

// ---------------------------------------------------------------------------
// Phase 6.5 — community scan flow
// ---------------------------------------------------------------------------

import {
  createRestaurant,
  decideRunItem,
  fetchRunItems,
  friendlyIngestionError,
  type IngestionItemPayload,
} from '../ingestion';

const sampleItem: IngestionItemPayload = {
  id: 'item-1',
  ingestion_run_id: 'rrrr-1111',
  item_id: null,
  name: 'Pad Thai',
  description: 'Rice noodles, peanut, lime.',
  section_name: 'Noodles',
  decision: 'pending',
  decided_at: null,
  ingredients_payload: [{ slug: 'nut-peanut', confidence: 0.97 }],
  tags_payload: [{ slug: 'cuisine-thai', confidence: 0.99 }],
  prices_payload: [{ size: null, price_cents: 1450 }],
  unresolved_ingredients: [],
  unresolved_tags: [],
};

describe('createRestaurant', () => {
  it('returns created on 201', async () => {
    const fetchImpl = fakeFetch(201, { id: 'r-1', slug: 'marias', name: "Maria's", status: 'draft' });

    const result = await createRestaurant({ name: "Maria's", citySlug: 'durango', fetchImpl });

    expect(result).toEqual({
      kind: 'created',
      restaurant: { id: 'r-1', slug: 'marias', name: "Maria's", status: 'draft' },
    });
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('/api/restaurants');
    expect(JSON.parse(init.body as string)).toMatchObject({ name: "Maria's", city_slug: 'durango' });
  });

  it('returns the candidate list on 409 instead of throwing', async () => {
    const candidates = [
      { id: 'r-9', slug: 'marias', name: "Maria's Tacos", status: 'published', street: '742 Main Ave' },
    ];
    const fetchImpl = fakeFetch(409, { error: 'possible_duplicate', candidates });

    const result = await createRestaurant({ name: 'Marias Taco', citySlug: 'durango', fetchImpl });

    expect(result).toEqual({ kind: 'duplicates', candidates });
  });

  it('sends force: "true" when overriding the dedup prompt', async () => {
    const fetchImpl = fakeFetch(201, { id: 'r-2', slug: 'x', name: 'X', status: 'draft' });

    await createRestaurant({ name: 'X', citySlug: 'durango', force: true, fetchImpl });

    const [, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(JSON.parse(init.body as string).force).toBe('true');
  });

  it('throws IngestionRequestError on other failures', async () => {
    const fetchImpl = fakeFetch(404, { error: 'unknown_city' });

    await expect(
      createRestaurant({ name: 'X', citySlug: 'atlantis', fetchImpl }),
    ).rejects.toBeInstanceOf(IngestionRequestError);
  });
});

describe('fetchRunItems / decideRunItem', () => {
  it('unwraps the items array', async () => {
    const fetchImpl = fakeFetch(200, { items: [sampleItem] });

    const items = await fetchRunItems('rrrr-1111', fetchImpl);

    expect(items).toHaveLength(1);
    expect(items[0]!.name).toBe('Pad Thai');
  });

  it('PATCHes the decision to the per-item proxy route', async () => {
    const fetchImpl = fakeFetch(200, { ...sampleItem, decision: 'accepted' });

    const updated = await decideRunItem({
      runId: 'rrrr-1111',
      itemId: 'item-1',
      decision: 'accepted',
      fetchImpl,
    });

    expect(updated.decision).toBe('accepted');
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('/api/ingestion_runs/rrrr-1111/items/item-1');
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(init.body as string)).toEqual({ decision: 'accepted' });
  });
});

describe('friendlyIngestionError', () => {
  it('maps 429 quota errors with the limit', () => {
    const err = new IngestionRequestError(429, { error: 'quota_exceeded', limit: 5 } as never);
    expect(friendlyIngestionError(err)).toBe('Daily scan limit reached (5/day) — try again tomorrow.');
  });

  it('maps 503 ceiling errors', () => {
    const err = new IngestionRequestError(503, { error: 'cost_ceiling_reached' });
    expect(friendlyIngestionError(err)).toMatch(/budget.*used up/);
  });

  it('maps 403 forbidden_restaurant', () => {
    const err = new IngestionRequestError(403, { error: 'forbidden_restaurant' });
    expect(friendlyIngestionError(err)).toMatch(/someone else's draft/);
  });

  it('falls back to the raw message otherwise', () => {
    expect(friendlyIngestionError(new Error('boom'))).toBe('boom');
  });
});
