/**
 * Phase 4.8 — proxy GET /api/profile/history to Rails with the
 * bw_session cookie's JWT.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function GET(request: NextRequest) {
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }
  const search = request.nextUrl.search ?? '';
  const upstream = await fetch(`${API_BASE}/api/v1/profile/history${search}`, {
    headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
  });
  const body = await upstream.text();
  return new NextResponse(body, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
