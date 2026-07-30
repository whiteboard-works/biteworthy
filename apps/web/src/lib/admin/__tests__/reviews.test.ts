import { describe, expect, it, vi } from 'vitest';

/**
 * The moderation fetchers' contract: filter params serialize exactly,
 * hide POSTs the chosen reason as JSON (it becomes author-facing
 * copy — a dropped body would 422), unhide POSTs bare.
 */
import { fetchModerationReviews, hideReview, unhideReview } from '../reviews';

function ok(body: unknown) {
  return vi.fn().mockResolvedValue({ ok: true, json: async () => body });
}

describe('admin reviews lib', () => {
  it('serializes the visibility + paging params', async () => {
    const impl = ok({ reviews: [], pagination: { total: 0, limit: 25, offset: 0 } });
    await fetchModerationReviews(
      { visibility: 'hidden', limit: 25, offset: 50 },
      impl as unknown as typeof fetch,
    );
    expect(impl.mock.calls[0]![0]).toBe('/api/admin/reviews?visibility=hidden&limit=25&offset=50');
  });

  it('hide POSTs the reason as a JSON body', async () => {
    const impl = ok({ id: 'r1', hidden_reason: 'duplicate' });
    await hideReview('r1', 'duplicate', impl as unknown as typeof fetch);
    const [url, init] = impl.mock.calls[0]! as [
      string,
      { method: string; body?: string; headers?: Record<string, string> },
    ];
    expect(url).toBe('/api/admin/reviews/r1/hide');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body!)).toEqual({ reason: 'duplicate' });
    expect(init.headers?.['Content-Type']).toBe('application/json');
  });

  it('unhide POSTs without a body', async () => {
    const impl = ok({ id: 'r1', hidden_at: null });
    await unhideReview('r1', impl as unknown as typeof fetch);
    const [url, init] = impl.mock.calls[0]! as [string, { method: string; body?: string }];
    expect(url).toBe('/api/admin/reviews/r1/unhide');
    expect(init.method).toBe('POST');
    expect(init.body).toBeUndefined();
  });
});
