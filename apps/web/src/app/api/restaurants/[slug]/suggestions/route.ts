/**
 * Phase 4.10 — proxy GET /api/restaurants/:slug/suggestions
 * (owner-only queue) with the cookie's JWT.
 */
import { NextResponse } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function GET(
  _request: Request,
  context: { params: Promise<{ slug: string }> },
) {
  const { slug } = await context.params;
  const jwt = await getServerJwt();
  if (!jwt) return NextResponse.json({ error: 'Not signed in' }, { status: 401 });

  const upstream = await fetch(
    `${API_BASE}/api/v1/restaurants/${encodeURIComponent(slug)}/suggestions`,
    { headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' } },
  );
  const text = await upstream.text();
  return new NextResponse(text, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
