/**
 * Phase 6.5 — `POST /api/restaurants` proxies community restaurant
 * creation (Phase 6.2's endpoint) with the JWT from the HttpOnly
 * cookie. 409 possible_duplicate responses pass through verbatim so
 * the /ingest page can render the "did you mean…?" cards.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../lib/api-proxy';

export async function POST(request: NextRequest) {
  return proxyAuthed('/api/v1/restaurants', { method: 'POST', body: await request.text() });
}
