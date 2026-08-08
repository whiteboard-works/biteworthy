import { describe, expect, it, vi } from 'vitest';
import { createToken, listTokens, revokeToken } from '../mcp-tokens';

function jsonFetch(status: number, body: unknown) {
  return vi.fn(async () => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  })) as unknown as typeof fetch;
}

describe('mcp tokens', () => {
  // The one and only time this value exists anywhere it can be read.
  it('returns the secret from create', async () => {
    vi.stubGlobal('fetch', jsonFetch(201, { id: 't-1', name: 'Claude Code', scopes: [], secret: 'bw_mcp_x' }));

    expect((await createToken('Claude Code', [])).secret).toBe('bw_mcp_x');
  });

  // The vocabulary comes from the server so the UI cannot drift from the
  // registry the scopes are derived from.
  it('reads the grantable scopes off the list response', async () => {
    vi.stubGlobal('fetch', jsonFetch(200, { tokens: [], scopes: ['discovery:read'] }));

    expect((await listTokens()).scopes).toEqual(['discovery:read']);
  });

  it('surfaces the server message on a refusal', async () => {
    vi.stubGlobal('fetch', jsonFetch(422, { error: 'Unknown scope(s): menus:teleport.' }));

    await expect(createToken('x', ['menus:teleport'])).rejects.toThrow('menus:teleport');
  });

  it('treats a 204 revoke as done', async () => {
    vi.stubGlobal('fetch', jsonFetch(204, null));

    await expect(revokeToken('t-1')).resolves.toBeUndefined();
  });
});
