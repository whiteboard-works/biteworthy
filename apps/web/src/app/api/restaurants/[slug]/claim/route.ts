/**
 * Phase 4.9 — proxy POST /api/restaurants/:slug/claim (request a
 * claim verification email) + GET /api/restaurants/:slug/claim/verify
 * (anonymous token verification).
 *
 * POST is auth-gated and runs through the cookie's JWT. GET is
 * anonymous (the URL token IS the credential), so we forward
 * straight through with no auth header.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ slug: string }> },
) {
  const { slug } = await context.params;
  const jwt = await getServerJwt();
  if (!jwt) return NextResponse.json({ error: 'Not signed in' }, { status: 401 });

  const body = await request.text();
  const upstream = await fetch(`${API_BASE}/api/v1/restaurants/${encodeURIComponent(slug)}/claim`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body,
  });
  const text = await upstream.text();
  return new NextResponse(text, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
