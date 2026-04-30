/**
 * Phase 4.1 — `POST /api/ingestion_runs` proxies multipart + JSON
 * upload bodies to Rails with the JWT from the HttpOnly cookie.
 * Lets the `/ingest` page kick off a run without the user pasting a
 * Bearer token.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../lib/server-auth';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export async function POST(request: NextRequest) {
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }

  const contentType = request.headers.get('Content-Type') ?? 'application/octet-stream';
  const isMultipart = contentType.startsWith('multipart/form-data');

  const headers: Record<string, string> = { Authorization: `Bearer ${jwt}` };
  // For multipart we have to forward the original boundary verbatim,
  // and the body has to stay a stream. JSON requests are simple text.
  let body: BodyInit;
  if (isMultipart) {
    headers['Content-Type'] = contentType;
    body = await request.arrayBuffer();
  } else {
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';
    body = await request.text();
  }

  const upstream = await fetch(`${API_BASE}/api/v1/ingestion_runs`, {
    method: 'POST',
    headers,
    body,
  });
  const responseText = await upstream.text();
  return new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
