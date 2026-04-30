/**
 * Phase 4.2 — proxy POST/DELETE /api/items/:id/never_hide to Rails
 * with the bw_session cookie's JWT injected as Bearer.
 *
 * Same pattern as the Phase 4.1 proxy routes for /api/profile and
 * /api/ingestion_runs.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

async function proxy(method: 'POST' | 'DELETE', id: string) {
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }
  const upstream = await fetch(`${API_BASE}/api/v1/items/${encodeURIComponent(id)}/never_hide`, {
    method,
    headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
  });
  const responseText = await upstream.text();
  return new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}

export async function POST(
  _request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  return proxy('POST', id);
}

export async function DELETE(
  _request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  return proxy('DELETE', id);
}
