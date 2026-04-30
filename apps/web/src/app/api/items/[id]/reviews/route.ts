/**
 * Phase 4.5 — proxy GET + POST /api/items/:id/reviews to Rails.
 *
 * GET is anonymous (mirrors the public Rails endpoint).
 * POST proxies multipart or JSON, injecting the cookie's JWT as
 * Bearer. Same shape as the Phase 4.1 ingestion_runs proxy.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function GET(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  const search = request.nextUrl.search ?? '';
  const upstream = await fetch(
    `${API_BASE}/api/v1/items/${encodeURIComponent(id)}/reviews${search}`,
    { headers: { Accept: 'application/json' } },
  );
  const body = await upstream.text();
  return new NextResponse(body, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }

  const contentType = request.headers.get('Content-Type') ?? 'application/octet-stream';
  const isMultipart = contentType.startsWith('multipart/form-data');

  const headers: Record<string, string> = { Authorization: `Bearer ${jwt}` };
  let body: BodyInit;
  if (isMultipart) {
    headers['Content-Type'] = contentType;
    body = await request.arrayBuffer();
  } else {
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';
    body = await request.text();
  }

  const upstream = await fetch(
    `${API_BASE}/api/v1/items/${encodeURIComponent(id)}/reviews`,
    { method: 'POST', headers, body },
  );
  const responseText = await upstream.text();
  return new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
