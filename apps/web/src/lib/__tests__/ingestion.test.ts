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
  it('POSTs JSON body with restaurant_id + source_url and returns the run', async () => {
    const fetchImpl = fakeFetch(201, sampleRun);

    const result = await ingestFromUrl({
      restaurantId: 'rest-1',
      sourceUrl: 'https://restaurant.example/menu',
      jwt: 'jwt-x',
      fetchImpl,
    });

    expect(result.id).toBe(sampleRun.id);
    const calls = fetchImpl.mock.calls as unknown as Array<[string, RequestInit]>;
    const [url, init] = calls[0]!;
    expect(url).toContain('/api/v1/ingestion_runs');
    expect(init.method).toBe('POST');
    expect(init.headers).toMatchObject({
      Authorization: 'Bearer jwt-x',
      'Content-Type': 'application/json',
    });
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
        jwt: 'jwt-x',
        fetchImpl,
      }),
    ).rejects.toMatchObject({
      status: 422,
      body: { error: 'url_fetch_failed', reason: 'non_2xx', status: 503 },
    });
  });
});

describe('ingestFromFile', () => {
  it('POSTs multipart with the file under inputs[]', async () => {
    const fetchImpl = fakeFetch(201, { ...sampleRun, input_kind: 'pdf' });
    const file = new File(['%PDF-1.4'], 'menu.pdf', { type: 'application/pdf' });

    const result = await ingestFromFile({
      restaurantId: 'rest-1',
      file,
      jwt: 'jwt-x',
      fetchImpl,
    });

    expect(result.input_kind).toBe('pdf');
    const calls = fetchImpl.mock.calls as unknown as Array<[string, RequestInit]>;
    const [, init] = calls[0]!;
    expect(init.method).toBe('POST');
    expect(init.headers).toMatchObject({ Authorization: 'Bearer jwt-x' });
    // No Content-Type — let fetch set the multipart boundary itself.
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
        jwt: 'jwt-x',
        fetchImpl: fetchImpl as unknown as typeof fetch,
      }),
    ).rejects.toBeInstanceOf(IngestionRequestError);
  });
});
