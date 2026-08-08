/**
 * Shared plumbing for the `/api/*` route handlers that proxy to the
 * Rails API.
 *
 * Every handler does the same two things: forward the request to Rails
 * with the session JWT (from the HttpOnly `bw_session` cookie) as a
 * Bearer token, and relay the upstream response back to the browser
 * verbatim. This is the one place that logic lives.
 *
 * Handlers with non-standard shapes keep their own code: multipart
 * uploads (`ingestion_runs`, item reviews) forward the raw body +
 * boundary; optional-auth routes (`items/:id/suggestions`) don't 401;
 * `auth/[action]` sets cookies. Those import nothing from here.
 */
import { NextResponse } from 'next/server';
import { API_BASE } from './api-base';
import { getServerJwt } from './server-auth';

/**
 * Relay a Rails response back to the browser verbatim — same status,
 * body, and Content-Type (defaulting to JSON when upstream omits it).
 */
export async function relayUpstream(upstream: Response): Promise<NextResponse> {
  const body = await upstream.text();
  return new NextResponse(body, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}

export interface ProxyInit {
  method?: string;
  /** Forwarded request body (mutations). Adds the JSON Content-Type. */
  body?: string;
  /** Passed through to `fetch` — e.g. `'no-store'` for status polling. */
  cache?: RequestCache;
}

/**
 * Forward to `${API_BASE}${apiPath}` with the session JWT as a Bearer
 * token and relay the response. Returns a 401 when the caller isn't
 * signed in. Pass `body` for mutations (GET/DELETE omit it, and the
 * JSON Content-Type that goes with it).
 */
export async function proxyAuthed(apiPath: string, init: ProxyInit = {}): Promise<NextResponse> {
  const jwt = await getServerJwt();
  if (!jwt) return NextResponse.json({ error: 'Not signed in' }, { status: 401 });

  const headers: Record<string, string> = {
    Authorization: `Bearer ${jwt}`,
    Accept: 'application/json',
  };
  if (init.body !== undefined) headers['Content-Type'] = 'application/json';

  const upstream = await fetch(`${API_BASE}${apiPath}`, {
    method: init.method ?? 'GET',
    headers,
    ...(init.body !== undefined ? { body: init.body } : {}),
    ...(init.cache !== undefined ? { cache: init.cache } : {}),
  });
  return relayUpstream(upstream);
}

/**
 * Forward a POST and relay the upstream body **without buffering it**, so
 * a chat turn's events reach the browser as they happen rather than all
 * at once when the turn ends.
 *
 * `relayUpstream` can't be used here: it awaits `.text()`, which waits for
 * the whole minute-long turn. A refusal still arrives complete and JSON
 * (the API validates before opening its stream), so those relay normally.
 */
export async function proxyStream(apiPath: string, body: string): Promise<Response> {
  const jwt = await getServerJwt();
  if (!jwt) return NextResponse.json({ error: 'Not signed in' }, { status: 401 });

  const upstream = await fetch(`${API_BASE}${apiPath}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
      Accept: 'text/event-stream',
    },
    body,
  });
  if (!upstream.ok || !upstream.body) return relayUpstream(upstream);

  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-store',
      // Proxies buffer by default, which would hold every event until the
      // turn ended and defeat the point of streaming.
      'X-Accel-Buffering': 'no',
    },
  });
}

/**
 * `proxyAuthed` + `Cache-Control: no-store` on the relayed response.
 * Admin JSON must never be browser/CDN-cacheable; `relayUpstream`
 * only mirrors Content-Type, so every `/api/admin/*` handler goes
 * through this wrapper instead of calling `proxyAuthed` directly.
 */
export async function adminProxy(apiPath: string, init: ProxyInit = {}): Promise<NextResponse> {
  const res = await proxyAuthed(apiPath, init);
  res.headers.set('Cache-Control', 'no-store');
  return res;
}
