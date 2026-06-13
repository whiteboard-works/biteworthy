/**
 * Phase 6.5 — `GET /api/ingestion_runs/:id` proxies run-status
 * polling for the web verify flow.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../lib/server-auth';

import { API_BASE } from '../../../../lib/api-base';

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }
  const { id } = await params;
  const upstream = await fetch(`${API_BASE}/api/v1/ingestion_runs/${encodeURIComponent(id)}`, {
    headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
    cache: 'no-store',
  });
  const responseText = await upstream.text();
  return new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
