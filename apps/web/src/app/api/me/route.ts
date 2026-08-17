/**
 * `/api/me` proxies to Rails with the JWT from the HttpOnly
 * `bw_session` cookie — the client never touches the JWT in JS.
 *
 * GET is the caller's own identity payload (handle, display_name,
 * is_admin). PATCH is self-service account editing — currently just
 * `handle`. `no-store` on the read: a stale handle would render the
 * wrong public identity in the settings form.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../lib/api-proxy';

export async function GET() {
  return proxyAuthed('/api/v1/me', { cache: 'no-store' });
}

export async function PATCH(request: NextRequest) {
  return proxyAuthed('/api/v1/me', { method: 'PATCH', body: await request.text() });
}
