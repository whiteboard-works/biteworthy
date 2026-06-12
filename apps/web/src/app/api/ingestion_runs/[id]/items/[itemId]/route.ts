/**
 * Phase 6.5 — `PATCH /api/ingestion_runs/:id/items/:itemId` proxies
 * accept / reject / edit decisions from the web verify page.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function PATCH(
  request: NextRequest,
  context: { params: Promise<{ id: string; itemId: string }> },
) {
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }
  const { id, itemId } = await context.params;
  const body = await request.text();
  const upstream = await fetch(
    `${API_BASE}/api/v1/ingestion_runs/${encodeURIComponent(id)}/items/${encodeURIComponent(itemId)}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${jwt}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body,
    },
  );
  const responseText = await upstream.text();
  return new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
