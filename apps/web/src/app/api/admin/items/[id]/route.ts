/**
 * `PATCH /api/admin/items/:id` — the deep edit: name, description,
 * status (removed = unpublish), section, ingredient/tag slugs, variants
 * and modifiers, plus photo upload/removal. Accepts multipart/form-data
 * for photo uploads or JSON for edits without photo changes.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';
import { API_BASE } from '../../../../../lib/api-base';
import { edgeHeaders } from '../../../../../lib/edge-headers';

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }

  const contentType = request.headers.get('Content-Type') ?? 'application/json';
  const isMultipart = contentType.startsWith('multipart/form-data');

  const headers: Record<string, string> = {
    Authorization: `Bearer ${jwt}`,
    ...(await edgeHeaders()),
  };
  let body: BodyInit;
  if (isMultipart) {
    headers['Content-Type'] = contentType;
    body = await request.arrayBuffer();
  } else {
    headers['Content-Type'] = 'application/json';
    body = await request.text();
  }

  const upstream = await fetch(
    `${API_BASE}/api/v1/admin/items/${encodeURIComponent(id)}`,
    { method: 'PATCH', headers, body },
  );
  const responseText = await upstream.text();
  const response = new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
  response.headers.set('Cache-Control', 'no-store');
  return response;
}

// `hard=true` is forwarded explicitly rather than relaying the whole
// query string: it is the one parameter this endpoint takes, and a
// blanket forward would hand arbitrary caller-controlled params to an
// admin route for no benefit.
function hardSuffix(request: NextRequest): string {
  return request.nextUrl.searchParams.get('hard') === 'true' ? '?hard=true' : '';
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }

  const headers: Record<string, string> = {
    Authorization: `Bearer ${jwt}`,
    Accept: 'application/json',
    ...(await edgeHeaders()),
  };

  const upstream = await fetch(
    `${API_BASE}/api/v1/admin/items/${encodeURIComponent(id)}${hardSuffix(request)}`,
    { method: 'DELETE', headers },
  );
  const responseText = await upstream.text();
  const response = new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
  response.headers.set('Cache-Control', 'no-store');
  return response;
}
