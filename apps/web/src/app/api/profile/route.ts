/**
 * Phase 4.1 — `PATCH /api/profile` proxies to Rails with the JWT
 * from the HttpOnly `bw_session` cookie. Lets the onboarding page
 * call `saveProfile` without ever touching the JWT in JS.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function PATCH(request: NextRequest) {
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }
  const body = await request.text();
  const upstream = await fetch(`${API_BASE}/api/v1/profile`, {
    method: 'PATCH',
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
