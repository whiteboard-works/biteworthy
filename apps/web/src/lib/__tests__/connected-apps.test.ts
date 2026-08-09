import { describe, expect, it, vi } from 'vitest';
import { NotSignedInError } from '../chat';
import { disconnectApp, listConnectedApps } from '../connected-apps';

function jsonFetch(status: number, body: unknown) {
  return vi.fn(async () => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  })) as unknown as typeof fetch;
}

describe('connected apps', () => {
  // The descriptions are what someone reads before deciding to
  // disconnect. They come from the server so this list says exactly what
  // the consent screen said — the UI never writes its own copy for a
  // scope.
  it('carries the server-rendered scope sentences through', async () => {
    vi.stubGlobal(
      'fetch',
      jsonFetch(200, {
        apps: [
          {
            id: 'a-1',
            name: 'Claude Desktop',
            redirect_host: 'claude.ai',
            scopes: ['profile:read'],
            scope_details: [{ scope: 'profile:read', description: 'See what you avoid' }],
            connected_at: '2026-08-09T00:00:00Z',
            last_renewed_at: null,
          },
        ],
      }),
    );

    const apps = await listConnectedApps();
    expect(apps[0]?.scope_details[0]?.description).toBe('See what you avoid');
  });

  it('unwraps an empty list rather than returning the envelope', async () => {
    vi.stubGlobal('fetch', jsonFetch(200, { apps: [] }));

    expect(await listConnectedApps()).toEqual([]);
  });

  // A signed-out caller must be distinguishable from a failed request, or
  // the settings page shows an error where it should send someone to log
  // in — same contract the other authed libs hold to.
  it('raises NotSignedInError on a 401', async () => {
    vi.stubGlobal('fetch', jsonFetch(401, null));

    await expect(listConnectedApps()).rejects.toBeInstanceOf(NotSignedInError);
  });

  it('treats a 204 disconnect as done', async () => {
    vi.stubGlobal('fetch', jsonFetch(204, null));

    await expect(disconnectApp('a-1')).resolves.toBeUndefined();
  });

  it('surfaces the server message on a refusal', async () => {
    vi.stubGlobal('fetch', jsonFetch(404, { error: 'No such connected app.' }));

    await expect(disconnectApp('a-9')).rejects.toThrow('No such connected app.');
  });
});
