import { describe, expect, it, vi } from 'vitest';
import {
  createReview,
  deleteReview,
  fetchReviews,
  ReviewError,
  updateReview,
  type ReviewPayload,
  type ReviewsResponse,
} from '../reviews';

const sampleReview: ReviewPayload = {
  id: 'rev-1',
  item_id: 'item-1',
  user: { id: 'u-1', handle: 'diner', display_name: 'Diner' },
  rating: 5,
  body: 'Loved it.',
  photo_url: null,
  created_at: '2026-04-30T10:00:00Z',
  updated_at: '2026-04-30T10:00:00Z',
};

const sampleResponse: ReviewsResponse = {
  item_id: 'item-1',
  reviews: [sampleReview],
  total: 1,
};

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

describe('fetchReviews', () => {
  it('GETs the Next proxy at /api/items/:id/reviews with credentials', async () => {
    const fetchImpl = fakeFetch(200, sampleResponse);
    const out = await fetchReviews('item-1', { fetchImpl });
    expect(out.total).toBe(1);

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/items/item-1/reviews');
    expect(init.credentials).toBe('same-origin');
  });

  it('passes limit + offset query params when supplied', async () => {
    const fetchImpl = fakeFetch(200, sampleResponse);
    await fetchReviews('item-1', { fetchImpl, limit: 5, offset: 10 });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('limit=5');
    expect(url).toContain('offset=10');
  });

  it('omits both when undefined', async () => {
    const fetchImpl = fakeFetch(200, sampleResponse);
    await fetchReviews('item-1', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).not.toContain('limit=');
    expect(url).not.toContain('offset=');
  });

  it('throws ReviewError on non-2xx', async () => {
    const fetchImpl = fakeFetch(404, { error: 'not found' });
    await expect(fetchReviews('missing', { fetchImpl })).rejects.toBeInstanceOf(ReviewError);
  });
});

describe('createReview', () => {
  it('POSTs JSON when no photo is supplied (no client-side Authorization)', async () => {
    const fetchImpl = fakeFetch(201, sampleReview);
    await createReview('item-1', { rating: 5, body: 'Great' }, { fetchImpl });

    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
    expect((init.headers as Record<string, string>)['Content-Type']).toBe('application/json');
    expect(JSON.parse(init.body as string)).toEqual({ rating: 5, body: 'Great' });
  });

  it('POSTs multipart when a File is attached', async () => {
    const fetchImpl = fakeFetch(201, sampleReview);
    const photo = new File(['fake'], 'photo.jpg', { type: 'image/jpeg' });
    await createReview('item-1', { rating: 4, body: 'See pic', photo }, { fetchImpl });

    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(init.body).toBeInstanceOf(FormData);
    expect((init.headers as Record<string, string> | undefined)?.['Content-Type']).toBeUndefined();
  });

  it('throws ReviewError on validation failure', async () => {
    const fetchImpl = fakeFetch(422, { error: 'Rating must be in 1..5' });
    await expect(createReview('item-1', { rating: 99 }, { fetchImpl })).rejects.toBeInstanceOf(
      ReviewError,
    );
  });

  it('surfaces a 401 ReviewError with the right status (caller bounces to /login)', async () => {
    const fetchImpl = fakeFetch(401, { error: 'Not signed in' });
    await expect(createReview('item-1', { rating: 5 }, { fetchImpl })).rejects.toMatchObject({
      status: 401,
    });
  });
});

describe('updateReview', () => {
  it('PATCHes /api/reviews/:id', async () => {
    const fetchImpl = fakeFetch(200, sampleReview);
    await updateReview('rev-1', { rating: 4 }, { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/reviews/rev-1');
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(init.body as string)).toEqual({ rating: 4 });
  });

  it('throws on 403 with status preserved', async () => {
    const fetchImpl = fakeFetch(403, { error: 'Only author' });
    await expect(updateReview('rev-1', { rating: 1 }, { fetchImpl })).rejects.toMatchObject({
      status: 403,
    });
  });
});

describe('deleteReview', () => {
  it('DELETEs the proxy URL', async () => {
    const fetchImpl = fakeFetch(204, {});
    await deleteReview('rev-1', { fetchImpl });
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(init.method).toBe('DELETE');
    expect(init.credentials).toBe('same-origin');
  });
});
