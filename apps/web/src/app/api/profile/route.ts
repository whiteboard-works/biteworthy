/**
 * Phase 4.1 — `PATCH /api/profile` proxies to Rails with the JWT
 * from the HttpOnly `bw_session` cookie. Lets the onboarding page
 * call `saveProfile` without ever touching the JWT in JS.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../lib/api-proxy';

export async function PATCH(request: NextRequest) {
  return proxyAuthed('/api/v1/profile', { method: 'PATCH', body: await request.text() });
}
