import { describe, expect, it, vi } from 'vitest';

/**
 * The runs fetchers are the moderation inbox's contract with the
 * proxy: filter params must serialize exactly (a typo\'d param is
 * silently ignored by Rails and the queue quietly shows everything),
 * the two levers must POST to the right member routes, and Rails
 * error codes must survive into AdminError so the detail page can map
 * already_published / has_promoted_items to instructions.
 */
import { AdminError } from '../shared';
import { confirmCommunity, fetchAdminRuns, reExtractRun } from '../runs';

function ok(body: unknown) {
  return vi.fn().mockResolvedValue({ ok: true, json: async () => body });
}

describe('fetchAdminRuns', () => {
  it('hits the bare queue path when no filters are set', async () => {
    const impl = ok({ runs: [], pagination: { total: 0, limit: 25, offset: 0 } });
    await fetchAdminRuns({}, impl as unknown as typeof fetch);
    expect(impl.mock.calls[0]![0]).toBe('/api/admin/ingestion_runs');
  });

  it('serializes every filter with the exact param names Rails reads', async () => {
    const impl = ok({ runs: [], pagination: { total: 0, limit: 10, offset: 20 } });
    await fetchAdminRuns(
      { status: 'staged', community: true, restaurantId: 'r-1', limit: 10, offset: 20 },
      impl as unknown as typeof fetch,
    );
    expect(impl.mock.calls[0]![0]).toBe(
      '/api/admin/ingestion_runs?status=staged&community=true&restaurant_id=r-1&limit=10&offset=20',
    );
  });
});

describe('admin run actions', () => {
  it('POSTs re-extract and confirm-community to their member routes', async () => {
    const impl = ok({ id: 'run-1', status: 'queued' });
    await reExtractRun('run-1', impl as unknown as typeof fetch);
    expect(impl.mock.calls[0]![0]).toBe('/api/admin/ingestion_runs/run-1/re_extract');
    expect((impl.mock.calls[0]![1] as { method: string }).method).toBe('POST');

    const impl2 = ok({ restaurant_id: 'rest-1', confirmed: { items: 1, ingredients: 2, tags: 0 } });
    await confirmCommunity('rest-1', impl2 as unknown as typeof fetch);
    expect(impl2.mock.calls[0]![0]).toBe('/api/admin/restaurants/rest-1/confirm_community');
    expect((impl2.mock.calls[0]![1] as { method: string }).method).toBe('POST');
  });

  it('carries the Rails error code so the page can explain the refusal', async () => {
    const impl = vi.fn().mockResolvedValue({
      ok: false,
      status: 422,
      json: async () => ({ error: 'has_promoted_items' }),
    });
    const err = await reExtractRun('run-1', impl as unknown as typeof fetch).catch(
      (e: unknown) => e,
    );
    expect(err).toBeInstanceOf(AdminError);
    expect((err as AdminError).code).toBe('has_promoted_items');
    expect((err as AdminError).status).toBe(422);
  });
});
