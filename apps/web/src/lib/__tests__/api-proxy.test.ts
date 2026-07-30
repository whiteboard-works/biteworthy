import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { adminProxy, proxyAuthed, relayUpstream } from '../api-proxy';

/**
 * The proxy plumbing shared by every authenticated `/api/*` route
 * handler. These handlers had no tests before the extraction — this
 * file is the coverage for the logic they now delegate to.
 */

const mockGetServerJwt = vi.fn();
vi.mock('../server-auth', () => ({
  getServerJwt: () => mockGetServerJwt(),
}));

const API_BASE = 'http://localhost:3000';

beforeEach(() => {
  mockGetServerJwt.mockReset().mockResolvedValue('jwt-123');
  vi.stubGlobal('fetch', vi.fn());
});

afterEach(() => {
  vi.unstubAllGlobals();
});

// Plain mock rather than `new Response(...)`, which auto-adds a
// text/plain Content-Type and so can't represent the "upstream omits
// Content-Type" case relayUpstream defaults for.
function upstream(body: string, status = 200, contentType: string | null = 'application/json') {
  return {
    status,
    text: async () => body,
    headers: { get: (name: string) => (name === 'Content-Type' ? contentType : null) },
  } as unknown as Response;
}

describe('relayUpstream', () => {
  it('mirrors status, body, and Content-Type', async () => {
    const res = await relayUpstream(upstream('{"ok":true}', 201, 'application/json'));
    expect(res.status).toBe(201);
    expect(await res.text()).toBe('{"ok":true}');
    expect(res.headers.get('Content-Type')).toBe('application/json');
  });

  it('defaults Content-Type to JSON when upstream omits it', async () => {
    const res = await relayUpstream(upstream('x', 200, null));
    expect(res.headers.get('Content-Type')).toBe('application/json');
  });
});

describe('proxyAuthed', () => {
  it('401s without calling Rails when the caller is not signed in', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    const res = await proxyAuthed('/api/v1/profile', { method: 'PATCH', body: '{}' });
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ error: 'Not signed in' });
    expect(fetch).not.toHaveBeenCalled();
  });

  it('forwards a GET with Bearer + Accept and no body / Content-Type', async () => {
    vi.mocked(fetch).mockResolvedValue(upstream('{"visits":[]}'));
    await proxyAuthed('/api/v1/profile/history?limit=5');

    const [url, init] = vi.mocked(fetch).mock.calls[0]!;
    expect(url).toBe(`${API_BASE}/api/v1/profile/history?limit=5`);
    expect(init?.method).toBe('GET');
    const headers = init?.headers as Record<string, string>;
    expect(headers.Authorization).toBe('Bearer jwt-123');
    expect(headers.Accept).toBe('application/json');
    expect(headers['Content-Type']).toBeUndefined();
    expect(init?.body).toBeUndefined();
  });

  it('forwards a mutation with the body and the JSON Content-Type', async () => {
    vi.mocked(fetch).mockResolvedValue(upstream('{"id":"r1"}', 200));
    await proxyAuthed('/api/v1/profile', { method: 'PATCH', body: '{"strictness":"strict"}' });

    const [url, init] = vi.mocked(fetch).mock.calls[0]!;
    expect(url).toBe(`${API_BASE}/api/v1/profile`);
    expect(init?.method).toBe('PATCH');
    expect(init?.body).toBe('{"strictness":"strict"}');
    expect((init?.headers as Record<string, string>)['Content-Type']).toBe('application/json');
  });

  it('passes cache through (e.g. no-store for status polling)', async () => {
    vi.mocked(fetch).mockResolvedValue(upstream('{}'));
    await proxyAuthed('/api/v1/ingestion_runs/abc', { cache: 'no-store' });
    expect(vi.mocked(fetch).mock.calls[0]![1]?.cache).toBe('no-store');
  });

  it('relays the upstream status + body back to the caller', async () => {
    vi.mocked(fetch).mockResolvedValue(upstream('{"error":"nope"}', 422));
    const res = await proxyAuthed('/api/v1/restaurants', { method: 'POST', body: '{}' });
    expect(res.status).toBe(422);
    expect(await res.json()).toEqual({ error: 'nope' });
  });
});

describe('adminProxy', () => {
  // Admin JSON must never be cacheable: a shared/CDN cache replaying an
  // admin payload to the next visitor would leak moderation data. The
  // wrapper exists solely to make forgetting the header impossible.
  it('stamps Cache-Control: no-store on relayed upstream responses', async () => {
    vi.mocked(fetch).mockResolvedValue(upstream('{"ok":true}'));
    const res = await adminProxy('/api/v1/admin/dashboard');
    expect(res.status).toBe(200);
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    expect(vi.mocked(fetch).mock.calls[0]![0]).toBe(`${API_BASE}/api/v1/admin/dashboard`);
  });

  it('keeps no-store on the local 401 (signed out) short-circuit too', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    const res = await adminProxy('/api/v1/admin/dashboard');
    expect(res.status).toBe(401);
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    expect(fetch).not.toHaveBeenCalled();
  });

  it('relays a Rails 404 (non-admin) verbatim', async () => {
    vi.mocked(fetch).mockResolvedValue(upstream('{"error":"not_found"}', 404));
    const res = await adminProxy('/api/v1/admin/dashboard');
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: 'not_found' });
  });
});
