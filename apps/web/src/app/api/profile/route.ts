/**
 * `/api/profile` proxies to Rails with the JWT from the HttpOnly
 * `bw_session` cookie — the client never touches the JWT in JS.
 *
 * PATCH (Phase 4.1) is the onboarding save. GET backs the account
 * page: it reads the caller's current dietary profile (with resolved
 * ingredient/tag names) so preferences can be shown and edited in
 * place. `no-store` — a stale profile would render wrong preferences.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../lib/api-proxy';

export async function GET() {
  return proxyAuthed('/api/v1/profile', { cache: 'no-store' });
}

export async function PATCH(request: NextRequest) {
  return proxyAuthed('/api/v1/profile', { method: 'PATCH', body: await request.text() });
}
