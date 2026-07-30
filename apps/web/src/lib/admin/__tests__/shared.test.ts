import { describe, expect, it, vi } from 'vitest';

/**
 * The admin data layer's single error class + JSON helper. Pages
 * branch on AdminError.status to decide between "sign in again",
 * "access lost", and a plain retry notice — so the status must ride
 * on the error, and the helper must always send the session cookie.
 */
import { AdminError, friendlyAdminError, getAdminJson } from '../shared';

describe('getAdminJson', () => {
  it('returns the parsed payload and sends same-origin credentials', async () => {
    const impl = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ n: 1 }) });
    await expect(getAdminJson<{ n: number }>('/api/admin/x', impl as unknown as typeof fetch))
      .resolves.toEqual({ n: 1 });
    expect(impl).toHaveBeenCalledWith('/api/admin/x', { credentials: 'same-origin' });
  });

  it('throws an AdminError carrying the HTTP status on non-2xx', async () => {
    const impl = vi.fn().mockResolvedValue({ ok: false, status: 404, json: async () => ({}) });
    const err = await getAdminJson('/api/admin/x', impl as unknown as typeof fetch).catch(
      (e: unknown) => e,
    );
    expect(err).toBeInstanceOf(AdminError);
    expect((err as AdminError).status).toBe(404);
  });
});

describe('friendlyAdminError', () => {
  it('maps 401 to sign-in copy and 403/404 to access-lost copy', () => {
    expect(friendlyAdminError(new AdminError('x', 401))).toMatch(/sign in/i);
    expect(friendlyAdminError(new AdminError('x', 403))).toMatch(/access/i);
    expect(friendlyAdminError(new AdminError('x', 404))).toMatch(/access/i);
  });

  it('falls back to retry copy for anything else', () => {
    expect(friendlyAdminError(new Error('boom'))).toMatch(/try again/i);
    expect(friendlyAdminError(new AdminError('x', 500))).toMatch(/try again/i);
  });
});
