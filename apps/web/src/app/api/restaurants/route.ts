/**
 * Phase 6.5 — `POST /api/restaurants` proxies community restaurant
 * creation (Phase 6.2's endpoint) with the JWT from the HttpOnly
 * cookie. 409 possible_duplicate responses pass through verbatim so
 * the /ingest page can render the "did you mean…?" cards.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../lib/server-auth';

import { API_BASE } from '../../../lib/api-base';

export async function POST(request: NextRequest) {
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }
  const body = await request.text();
  const upstream = await fetch(`${API_BASE}/api/v1/restaurants`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body,
  });
  const responseText = await upstream.text();
  return new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
