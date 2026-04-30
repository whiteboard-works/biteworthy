/**
 * Phase 4.9 — proxy GET /api/restaurants/:slug/claim/verify?t=<token>.
 * Anonymous: the token IS the credential. No cookie or auth header.
 */
import { NextResponse, type NextRequest } from 'next/server';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function GET(
  request: NextRequest,
  context: { params: Promise<{ slug: string }> },
) {
  const { slug } = await context.params;
  const search = request.nextUrl.search ?? '';
  const upstream = await fetch(
    `${API_BASE}/api/v1/restaurants/${encodeURIComponent(slug)}/claim/verify${search}`,
    { headers: { Accept: 'application/json' } },
  );
  const body = await upstream.text();
  return new NextResponse(body, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
