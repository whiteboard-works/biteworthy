/**
 * Phase 4.10 — proxy PATCH /api/suggestions/:id (owner accept/reject)
 * with the cookie's JWT.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function PATCH(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  const jwt = await getServerJwt();
  if (!jwt) return NextResponse.json({ error: 'Not signed in' }, { status: 401 });

  const body = await request.text();
  const upstream = await fetch(`${API_BASE}/api/v1/suggestions/${encodeURIComponent(id)}`, {
    method: 'PATCH',
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
