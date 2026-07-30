import { describe, expect, it, vi } from 'vitest';

/**
 * fetchDashboard is the ops dashboard's only data source; the thing
 * worth pinning is the proxy path (a typo here silently 404s and the
 * page reads it as "access lost") and that failures surface as
 * AdminError, which the page maps to friendly copy.
 */
import { AdminError } from '../shared';
import { fetchDashboard } from '../metrics';

describe('fetchDashboard', () => {
  it('reads /api/admin/dashboard through the proxy', async () => {
    const impl = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ok: 1 }) });
    await fetchDashboard(impl as unknown as typeof fetch);
    expect(impl.mock.calls[0]![0]).toBe('/api/admin/dashboard');
  });

  it('propagates non-2xx as AdminError', async () => {
    const impl = vi.fn().mockResolvedValue({ ok: false, status: 401, json: async () => ({}) });
    await expect(fetchDashboard(impl as unknown as typeof fetch)).rejects.toBeInstanceOf(
      AdminError,
    );
  });
});
