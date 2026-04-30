import {
  uploadIngestionRun,
  IngestionUploadError,
} from '../../lib/api/ingestion-runs';

describe('uploadIngestionRun', () => {
  const sampleRun = {
    id: 'd9e6c1f0-1111-4ddf-8da0-aaaa11112222',
    status: 'extracting',
    input_kind: 'photo',
    restaurant_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    state_history: { extracting: '2026-04-29T23:50:00Z' },
    failure_message: null,
    api_cost_cents: 0,
    latency_ms: null,
    input_count: 2,
    ingestion_items_count: 0,
    created_at: '2026-04-29T23:50:00Z',
    updated_at: '2026-04-29T23:50:00Z',
  };

  function fakeFetch(status: number, body: unknown) {
    return jest.fn(async () =>
      ({
        ok: status >= 200 && status < 300,
        status,
        json: async () => body,
      }) as unknown as Response,
    );
  }

  it('POSTs multipart to /api/v1/ingestion_runs and returns the parsed run', async () => {
    const fetchImpl = fakeFetch(201, sampleRun);

    const result = await uploadIngestionRun({
      restaurantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      pages: [
        { uri: 'file:///mock/page-1.jpg' },
        { uri: 'file:///mock/page-2.jpg', mimeType: 'image/png' },
      ],
      jwt: 'sample-jwt',
      fetchImpl,
    });

    expect(result.id).toBe(sampleRun.id);
    expect(fetchImpl).toHaveBeenCalledTimes(1);

    const calls = fetchImpl.mock.calls as unknown as Array<[string, RequestInit]>;
    const init = calls[0]?.[1];
    expect(init?.method).toBe('POST');
    expect(init?.headers).toMatchObject({ Authorization: 'Bearer sample-jwt' });
    expect(init?.body).toBeDefined();
  });

  it('throws IngestionUploadError carrying status + body when the server rejects', async () => {
    const fetchImpl = fakeFetch(403, { error: 'forbidden' });

    await expect(
      uploadIngestionRun({
        restaurantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        pages: [{ uri: 'file:///mock/page-1.jpg' }],
        jwt: 'no-good-jwt',
        fetchImpl,
      }),
    ).rejects.toMatchObject({
      status: 403,
      body: { error: 'forbidden' },
    });
  });

  it('refuses to send when pages is empty', async () => {
    const fetchImpl = jest.fn();

    await expect(
      uploadIngestionRun({
        restaurantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        pages: [],
        jwt: 'sample-jwt',
        fetchImpl: fetchImpl as unknown as typeof fetch,
      }),
    ).rejects.toThrow(/at least one page/);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('survives a non-JSON error body', async () => {
    const fetchImpl = jest.fn(async () =>
      ({
        ok: false,
        status: 500,
        json: async () => {
          throw new Error('not json');
        },
      }) as unknown as Response,
    );

    await expect(
      uploadIngestionRun({
        restaurantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        pages: [{ uri: 'file:///mock/page-1.jpg' }],
        jwt: 'sample-jwt',
        fetchImpl: fetchImpl as unknown as typeof fetch,
      }),
    ).rejects.toBeInstanceOf(IngestionUploadError);
  });
});
