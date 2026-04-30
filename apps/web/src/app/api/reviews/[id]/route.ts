/**
 * Phase 4.5 — proxy PATCH + DELETE /api/reviews/:id to Rails with
 * the cookie's JWT. Owner-gated 403 lives on the Rails side.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

async function proxy(method: 'PATCH' | 'DELETE', id: string, request: NextRequest) {
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }

  const headers: Record<string, string> = { Authorization: `Bearer ${jwt}` };
  let body: BodyInit | undefined;
  if (method === 'PATCH') {
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';
    body = await request.text();
  }

  const upstream = await fetch(`${API_BASE}/api/v1/reviews/${encodeURIComponent(id)}`, {
    method,
    headers,
    body,
  });
  const responseText = await upstream.text();
  return new NextResponse(responseText.length > 0 ? responseText : null, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}

export async function PATCH(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  return proxy('PATCH', id, request);
}

export async function DELETE(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  return proxy('DELETE', id, request);
}
