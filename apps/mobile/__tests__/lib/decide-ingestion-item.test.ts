import {
  decideIngestionItem,
  getIngestionRun,
  listIngestionItems,
  IngestionUploadError,
} from '../../lib/api/ingestion-runs';

describe('decideIngestionItem', () => {
  function fakeFetch(status: number, body: unknown) {
    return jest.fn(async () =>
      ({
        ok: status >= 200 && status < 300,
        status,
        json: async () => body,
      }) as unknown as Response,
    );
  }

  const samplePayload = {
    id: 'iiii-1111',
    ingestion_run_id: 'rrrr-1111',
    item_id: 'item-1111',
    name: 'Carne Asada Taco',
    description: 'Grilled steak.',
    section_name: 'Tacos',
    decision: 'accepted',
    decided_at: '2026-04-30T00:00:00Z',
    ingredients_payload: [{ slug: 'meat-beef', confidence: 0.97 }],
    tags_payload: [{ slug: 'cuisine-mexican', confidence: 0.99 }],
    prices_payload: [{ size: null, price_cents: 450 }],
    unresolved_ingredients: [],
    unresolved_tags: [],
  };

  it('PATCHes /ingestion_runs/:run/items/:id with the decision', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);

    await decideIngestionItem({
      runId: 'rrrr-1111',
      itemId: 'iiii-1111',
      decision: 'accepted',
      jwt: 'jwt-x',
      fetchImpl,
    });

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const calls = fetchImpl.mock.calls as unknown as Array<[string, RequestInit]>;
    const [url, init] = calls[0]!;
    expect(url).toContain('/api/v1/ingestion_runs/rrrr-1111/items/iiii-1111');
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(init.body as string)).toEqual({ decision: 'accepted' });
  });

  it('includes edits payload when provided', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);

    await decideIngestionItem({
      runId: 'rrrr-1111',
      itemId: 'iiii-1111',
      decision: 'accepted',
      edits: { name: 'Steak Taco', description: 'House-marinated.' },
      jwt: 'jwt-x',
      fetchImpl,
    });

    const calls = fetchImpl.mock.calls as unknown as Array<[string, RequestInit]>;
    const body = JSON.parse(calls[0]![1].body as string);
    expect(body).toEqual({
      decision: 'accepted',
      name: 'Steak Taco',
      description: 'House-marinated.',
    });
  });

  it('throws IngestionUploadError on non-2xx', async () => {
    const fetchImpl = fakeFetch(403, { error: 'forbidden' });

    await expect(
      decideIngestionItem({
        runId: 'rrrr-1111',
        itemId: 'iiii-1111',
        decision: 'accepted',
        jwt: 'no-good-jwt',
        fetchImpl,
      }),
    ).rejects.toBeInstanceOf(IngestionUploadError);
  });
});

describe('getIngestionRun (poll target)', () => {
  it('returns the run payload on 200', async () => {
    const sample = {
      id: 'rrrr-1111',
      status: 'staged',
      input_kind: 'photo',
      restaurant_id: 'rest-1111',
      state_history: { staged: '2026-04-30T00:00:00Z' },
      failure_message: null,
      api_cost_cents: 12,
      latency_ms: 4500,
      input_count: 2,
      ingestion_items_count: 5,
      created_at: '2026-04-30T00:00:00Z',
      updated_at: '2026-04-30T00:00:00Z',
    };
    const fetchImpl = jest.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => sample,
    })) as unknown as typeof fetch;

    const result = await getIngestionRun('rrrr-1111', { jwt: 'jwt-x', fetchImpl });
    expect(result.status).toBe('staged');
    expect(result.ingestion_items_count).toBe(5);
  });
});

describe('listIngestionItems', () => {
  it('unwraps the items array', async () => {
    const sampleItems = [
      {
        id: 'i1',
        ingestion_run_id: 'rrrr-1111',
        item_id: null,
        name: 'A',
        description: null,
        section_name: null,
        decision: 'pending',
        decided_at: null,
        ingredients_payload: [],
        tags_payload: [],
        prices_payload: [],
        unresolved_ingredients: [],
        unresolved_tags: [],
      },
    ];
    const fetchImpl = jest.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({ items: sampleItems }),
    })) as unknown as typeof fetch;

    const items = await listIngestionItems('rrrr-1111', { jwt: 'jwt-x', fetchImpl });
    expect(items).toHaveLength(1);
    expect(items[0]?.id).toBe('i1');
  });
});
