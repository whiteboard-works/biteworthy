import {
  createReview,
  deleteReview,
  fetchReviews,
  ReviewError,
  updateReview,
  type ReviewPayload,
  type ReviewsResponse,
} from '../../lib/api/reviews';

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

describe('fetchReviews', () => {
  it('GETs /api/v1/items/:id/reviews and returns the parsed body', async () => {
    const fetchImpl = fakeFetch(200, sampleResponse);
    const out = await fetchReviews('item-1', { fetchImpl });
    expect(out.total).toBe(1);
    expect(String(fetchImpl.mock.calls[0]![0])).toContain('/api/v1/items/item-1/reviews');
  });

  it('passes limit + offset query params when supplied', async () => {
    const fetchImpl = fakeFetch(200, sampleResponse);
    await fetchReviews('item-1', { fetchImpl, limit: 5, offset: 10 });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('limit=5');
    expect(url).toContain('offset=10');
  });

  it('omits limit / offset when undefined', async () => {
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
  it('POSTs JSON with rating + body when no photo is supplied', async () => {
    const fetchImpl = fakeFetch(201, sampleReview);
    await createReview('item-1', 'jjj.www.ttt', { rating: 5, body: 'Great' }, { fetchImpl });

    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(init.method).toBe('POST');
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer jjj.www.ttt');
    expect((init.headers as Record<string, string>)['Content-Type']).toBe('application/json');
    expect(JSON.parse(init.body as string)).toEqual({ rating: 5, body: 'Great' });
  });

  it('POSTs multipart with the photo when photoUri is supplied', async () => {
    const fetchImpl = fakeFetch(201, sampleReview);
    await createReview(
      'item-1',
      'jwt',
      { rating: 4, body: 'See pic', photoUri: 'file:///tmp/photo.jpg', photoMimeType: 'image/jpeg' },
      { fetchImpl },
    );

    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(init.body).toBeInstanceOf(FormData);
    // Don't set Content-Type for multipart — fetch picks the boundary.
    expect((init.headers as Record<string, string>)['Content-Type']).toBeUndefined();
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer jwt');
  });

  it('throws ReviewError on validation failure', async () => {
    const fetchImpl = fakeFetch(422, { error: 'Rating must be in 1..5' });
    await expect(
      createReview('item-1', 'jwt', { rating: 99 }, { fetchImpl }),
    ).rejects.toBeInstanceOf(ReviewError);
  });
});

describe('updateReview', () => {
  it('PATCHes /api/v1/reviews/:id with the patch payload', async () => {
    const fetchImpl = fakeFetch(200, sampleReview);
    await updateReview('rev-1', 'jwt', { rating: 4 }, { fetchImpl });

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toContain('/api/v1/reviews/rev-1');
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(init.body as string)).toEqual({ rating: 4 });
  });

  it('throws ReviewError on 403', async () => {
    const fetchImpl = fakeFetch(403, { error: 'Only the author' });
    await expect(updateReview('rev-1', 'wrong-user', { rating: 1 }, { fetchImpl })).rejects.toMatchObject({
      status: 403,
    });
  });
});

describe('deleteReview', () => {
  it('DELETEs /api/v1/reviews/:id', async () => {
    const fetchImpl = fakeFetch(204, {});
    await deleteReview('rev-1', 'jwt', { fetchImpl });
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(init.method).toBe('DELETE');
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer jwt');
  });

  it('throws on non-2xx', async () => {
    const fetchImpl = fakeFetch(403, { error: 'forbidden' });
    await expect(deleteReview('rev-1', 'jwt', { fetchImpl })).rejects.toBeInstanceOf(ReviewError);
  });
});
